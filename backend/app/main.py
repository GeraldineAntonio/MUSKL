Warning: truncated output (original token count: 60754)
Total output lines: 4198

from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import smtplib
import urllib.request
import uuid
from urllib.parse import urlencode
from contextlib import asynccontextmanager, suppress
from datetime import UTC, date, datetime, timedelta
from email.message import EmailMessage
from pathlib import Path
from typing import Annotated, Literal

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from fastapi import (BackgroundTasks, Depends, FastAPI, File, Form, HTTPException,
                     Query, Request, UploadFile)
from fastapi.responses import RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import AfterValidator, BaseModel, EmailStr, Field, field_validator
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from psycopg.types.json import Jsonb

from .object_storage import (
    StorageNotConfigured,
    StorageReadError,
    StorageWriteError,
    delete_certificate,
    delete_profile_photo,
    presigned_certificate_url,
    presigned_profile_photo_url,
    put_certificate,
    put_profile_photo,
)

logging.basicConfig(level=logging.INFO)
log = logging.getLogger('muskl.api')

DATABASE_URL = os.environ['DATABASE_URL']
JWT_SECRET = os.environ['JWT_SECRET']
if len(JWT_SECRET) < 32:
    raise RuntimeError('JWT_SECRET debe tener al menos 32 caracteres.')
JWT_ALGORITHM = 'HS256'
ACCESS_TOKEN_MINUTES = 60
REFRESH_TOKEN_DAYS = 30
RESET_CODE_MINUTES = 10
UPLOAD_DIR = Path(os.getenv('MUSKL_UPLOAD_DIR', '/app/uploads'))
GYM_ID = '00000000-0000-4000-8000-000000000001'
password_hasher = PasswordHasher()
# Perform a password-hash verification for unknown identifiers too, reducing
# timing differences that could reveal whether an account exists.
DUMMY_PASSWORD_HASH = password_hasher.hash(secrets.token_urlsafe(32))
pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=10, open=False,
                     kwargs={'row_factory': dict_row})
bearer = HTTPBearer(auto_error=False)


@asynccontextmanager
async def lifespan(_: FastAPI):
    pool.open(wait=True)
    cleanup = asyncio.create_task(_expired_account_cleanup_loop())
    phase_maintenance = asyncio.create_task(_routine_phase_maintenance_loop())
    yield
    cleanup.cancel()
    phase_maintenance.cancel()
    with suppress(asyncio.CancelledError):
        await cleanup
    with suppress(asyncio.CancelledError):
        await phase_maintenance
    pool.close()


app = FastAPI(title='MUSKL API', version='0.1.0', lifespan=lifespan)
origins = [v.strip() for v in os.getenv('MUSKL_CORS_ORIGINS', '').split(',') if v.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins or ['*'],
                   allow_credentials=False, allow_methods=['*'], allow_headers=['*'])


def _purge_expired_account_deletions() -> int:
    """Permanently remove deactivated client/trainer records after 30 days."""
    photo_keys: list[str] = []
    certificate_keys: list[str] = []
    with pool.connection() as conn:
        with conn.cursor() as cur:
            targets = cur.execute("""SELECT u.id, u.gym_id, u.role, u.member_number,
                    u.profile_photo_storage_key
                FROM users u
                WHERE u.role IN ('client', 'trainer') AND u.status = 'deactivated'
                  AND u.reactivation_until <= now()
                ORDER BY u.reactivation_until LIMIT 100
                FOR UPDATE OF u SKIP LOCKED""").fetchall()
            if not targets:
                return 0
            photo_keys = [row['profile_photo_storage_key'] for row in targets
                          if row['profile_photo_storage_key']]
            user_ids = [row['id'] for row in targets]
            user_id_text = [str(user_id) for user_id in user_ids]
            member_numbers = [row['member_number'] for row in targets if row['member_number']]
            certificate_keys = [row['storage_key'] for row in cur.execute(
                'SELECT storage_key FROM trainer_certifications WHERE trainer_id = ANY(%s)',
                (user_ids,)).fetchall()]

            # Keep audit event type/timestamp, but remove details that may contain
            # personal data. Relational references are SET NULL by migration 004.
            cur.execute("""UPDATE account_audit_events
                SET details = '{}'::jsonb
                WHERE actor_id = ANY(%s) OR subject_id = ANY(%s)
                   OR details->>'client_id' = ANY(%s)
                   OR details->>'trainer_id' = ANY(%s)""",
                (user_ids, user_ids, user_id_text, user_id_text))
            cur.execute("UPDATE account_deletion_requests SET note = NULL WHERE user_id = ANY(%s)",
                        (user_ids,))
            cur.execute("""DELETE FROM notifications
                WHERE payload->>'client_id' = ANY(%s)
                   OR payload->>'trainer_id' = ANY(%s)
                   OR payload->>'user_id' = ANY(%s)""",
                (user_id_text, user_id_text, user_id_text))
            deleted = cur.execute("DELETE FROM users WHERE id = ANY(%s) RETURNING gym_id",
                                  (user_ids,)).fetchall()
            if member_numbers:
                cur.execute("""DELETE FROM client_groups g
                    WHERE g.member_number = ANY(%s)
                      AND NOT EXISTS (SELECT 1 FROM client_group_members gm WHERE gm.group_id = g.id)""",
                    (member_numbers,))
            by_gym: dict[uuid.UUID, int] = {}
            for row in deleted:
                by_gym[row['gym_id']] = by_gym.get(row['gym_id'], 0) + 1
            for gym_id, count in by_gym.items():
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, event_type, details)
                    VALUES (%s, 'account_data_purged', %s)""",
                    (gym_id, Jsonb({'accounts': count})))
            deleted_count = len(deleted)
    for storage_key in photo_keys:
        try:
            delete_profile_photo(storage_key)
        except Exception:
            log.exception('Could not delete profile photo after account purge')
    for storage_key in certificate_keys:
        try:
            delete_certificate(storage_key)
            if storage_key.startswith('local://'):
                (UPLOAD_DIR / storage_key.removeprefix('local://')).unlink(missing_ok=True)
        except Exception:
            log.exception('Could not delete trainer certification after account purge')
    log.info('Purged %s expired client/trainer account(s)', deleted_count)
    return deleted_count


async def _expired_account_cleanup_loop() -> None:
    while True:
        try:
            await asyncio.to_thread(_purge_expired_account_deletions)
        except Exception:
            log.exception('Expired account cleanup failed; it will retry later')
        await asyncio.sleep(12 * 60 * 60)


async def _routine_phase_maintenance_loop() -> None:
    while True:
        try:
            await asyncio.to_thread(_process_due_routine_phases)
            await asyncio.to_thread(_deliver_trainer_daily_reminders)
        except Exception:
            log.exception('Routine phase maintenance failed; it will retry later')
        await asyncio.sleep(30 * 60)


def _validate_strong_password(value: str) -> str:
    requirements = (
        (r'[A-Z]', 'una letra mayúscula'),
        (r'[a-z]', 'una letra minúscula'),
        (r'\d', 'un número'),
        (r'[^A-Za-z0-9\s]', 'un carácter especial'),
    )
    missing = [label for pattern, label in requirements
               if not re.search(pattern, value)]
    if missing:
        raise ValueError('La contraseña debe contener ' + ', '.join(missing) + '.')
    return value


StrongPassword = Annotated[
    str,
    Field(min_length=8, max_length=128),
    AfterValidator(_validate_strong_password),
]


class ClientRegistration(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = Field(default=None, max_length=30)
    member_number: str = Field(min_length=1, max_length=40)
    member_registry_id: uuid.UUID | None = None
    birth_date: date
    password: StrongPassword
    photo_data: str | None = Field(default=None, max_length=2_800_000)
    photo_mime: Literal['image/jpeg', 'image/png'] | None = None

    @field_validator('birth_date')
    @classmethod
    def validate_birth_date(cls, value: date) -> date:
        if value > datetime.now(UTC).date():
            raise ValueError('La fecha de nacimiento no puede estar en el futuro.')
        return value


class MemberNumberLookup(BaseModel):
    member_number: str = Field(min_length=1, max_length=40)


class GroupMemberRegistration(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = Field(default=None, max_length=30)
    birth_date: date
    password: StrongPassword

    @field_validator('birth_date')
    @classmethod
    def validate_birth_date(cls, value: date) -> date:
        if value > datetime.now(UTC).date():
            raise ValueError('La fecha de nacimiento no puede estar en el futuro.')
        return value


class ClientGroupRegistration(BaseModel):
    plan_id: uuid.UUID
    members: list[GroupMemberRegistration] = Field(min_length=1, max_length=49)


class AdminRegistration(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = Field(default=None, max_length=30)
    password: StrongPassword
    invite_token: str = Field(min_length=8, max_length=100)
    photo_data: str | None = Field(default=None, max_length=2_800_000)
    photo_mime: Literal['image/jpeg', 'image/png'] | None = None


class PasswordCodeRequest(BaseModel):
    email: EmailStr


class PasswordChangeCodeRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)


class PasswordChangeCodeVerifyRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    code: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')


class RegistrationEmailCodeRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')


class RegistrationEmailResendRequest(BaseModel):
    email: EmailStr


class EmailChangeRequest(BaseModel):
    new_email: EmailStr


class EmailChangeConfirmRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    code: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')


class VerifyCodeRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')


class ResetPasswordRequest(VerifyCodeRequest):
    new_password: StrongPassword


class DeactivationRequest(BaseModel):
    reason: Literal['Membresía vencida sin renovar', 'Incumplimiento de reglas',
                    'Solicitud del socio', 'Otro']
    note: str | None = Field(default=None, max_length=1000)


class StaffReviewRequest(BaseModel):
    approved: bool
    reason: str | None = Field(default=None, max_length=1000)


class AccountDeletionReview(BaseModel):
    approved: bool
    note: str | None = Field(default=None, max_length=1000)


class ReassignTrainerRequest(BaseModel):
    client_id: uuid.UUID
    new_trainer_id: uuid.UUID


class ClientOnboardingRequest(BaseModel):
    plan_id: uuid.UUID
    trainer_id: uuid.UUID | None = None
    goal: Literal['Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza']
    experience_level: Literal['principiante', 'intermedio', 'avanzado']
    days_per_week: int = Field(ge=3, le=6)
    weight_kg: float = Field(ge=20, le=350)
    height_cm: float | None = Field(default=None, ge=100, le=250)
    limitations: str | None = Field(default=None, max_length=2000)


class TrainerRequestCreate(BaseModel):
    trainer_id: uuid.UUID


class TrainerRequestAcceptance(BaseModel):
    routine_id: uuid.UUID | None = None
    phase_id: uuid.UUID | None = None


class ClientProfileUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=80)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=30)
    bio: str | None = Field(default=None, max_length=1000)
    photo_data: str | None = Field(default=None, max_length=2_800_000)
    photo_mime: Literal['image/jpeg', 'image/png'] | None = None
    remove_photo: bool = False


class ProfilePhotoUpdate(BaseModel):
    photo_data: str | None = Field(default=None, max_length=2_800_000)
    photo_mime: Literal['image/jpeg', 'image/png'] | None = None
    remove_photo: bool = False


class OwnProfileUpdate(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    phone: str | None = Field(default=None, max_length=30)
    bio: str | None = Field(default=None, max_length=1000)


class RoutineExerciseInput(BaseModel):
    catalog_id: uuid.UUID | None = None
    # Every item belongs to exactly one day. Leaving this optional caused the
    # API to copy an exercise onto every selected routine day.
    day_number: int = Field(ge=1, le=7)
    name: str = Field(min_length=1, max_length=120)
    sets: int = Field(default=4, ge=1, le=20)
    reps: str = Field(default='8-12', min_length=1, max_length=40)
    rest_seconds: int = Field(default=60, ge=0, le=3600)


class RoutineCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    goal: Literal['Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza']
    days: list[int] = Field(min_length=3, max_length=6)
    exercises: list[RoutineExerciseInput] = Field(min_length=1, max_length=40)

    @field_validator('days')
    @classmethod
    def validate_days(cls, value: list[int]) -> list[int]:
        if len(set(value)) != len(value) or any(day < 1 or day > 7 for day in value):
            raise ValueError('Los días deben ser únicos y estar entre 1 y 7.')
        return value

    @field_validator('exercises')
    @classmethod
    def validate_exercise_days(cls, value: list[RoutineExerciseInput], info):
        days = set(info.data.get('days', []))
        if any(ex.day_number not in days for ex in value):
            raise ValueError('Cada ejercicio debe pertenecer a uno de los días seleccionados.')
        return value


class RoutinePhaseCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    days: list[int] = Field(min_length=3, max_length=6)
    exercises: list[RoutineExerciseInput] = Field(min_length=1, max_length=40)

    @field_validator('days')
    @classmethod
    def validate_phase_days(cls, value: list[int]) -> list[int]:
        if len(set(value)) != len(value) or any(day < 1 or day > 7 for day in value):
            raise ValueError('Los días deben ser únicos y estar entre 1 y 7.')
        return value

    @field_validator('exercises')
    @classmethod
    def validate_phase_exercise_days(cls, value: list[RoutineExerciseInput], info):
        days = set(info.data.get('days', []))
        if any(ex.day_number not in days for ex in value):
            raise ValueError('Cada ejercicio debe pertenecer a uno de los días seleccionados.')
        return value


class WorkoutCompletionRequest(BaseModel):
    duration_seconds: int | None = Field(default=None, ge=1, le=86400)
    day_number: int | None = Field(default=None, ge=1, le=7)


class WorkoutSetProgressRequest(BaseModel):
    sets_completed: int = Field(ge=0, le=20)


class RoutineAssignmentRequest(BaseModel):
    client_id: uuid.UUID
    phase_id: uuid.UUID


class TrainerProfileUpdate(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = Field(default=None, max_length=30)
    specialty: str | None = Field(default=None, max_length=120)
    bio: str | None = Field(default=None, max_length=2000)
    notification_preferences: dict[str, bool] = Field(default_factory=dict)


class AdminPreferencesUpdate(BaseModel):
    new_requests: bool


class PasswordChangeRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: StrongPassword
    code: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')


class LoginRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=200)
    password: str = Field(min_length=1, max_length=128)


class SocialLoginRequest(BaseModel):
    identity_token: str | None = Field(default=None, min_length=20, max_length=10000)
    authorization_code: str | None = Field(default=None, min_length=10, max_length=4096)


class GoogleClientRegistration(BaseModel):
    identity_token: str = Field(min_length=20, max_length=10000)
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    phone: str | None = Field(default=None, max_length=30)
    member_number: str = Field(min_length=1, max_length=40)
    member_registry_id: uuid.UUID | None = None
    birth_date: date

    @field_validator('birth_date')
    @classmethod
    def validate_birth_date(cls, value: date) -> date:
        if value > datetime.now(UTC).date():
            raise ValueError('La fecha de nacimiento no puede estar en el futuro.')
        return value


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=200)


def _problem(status: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status, detail={'code': code, 'message': message})


def _decode_profile_photo(photo_data: str | None,
                          photo_mime: str | None) -> tuple[bytes, str] | None:
    if photo_data is None and photo_mime is None:
        return None
    if photo_data is None or photo_mime is None:
        raise _problem(415, 'INVALID_PROFILE_PHOTO', 'Faltan los datos de la foto seleccionada.')
    try:
        data = base64.b64decode(photo_data, validate=True)
    except (ValueError, binascii.Error):
        raise _problem(415, 'INVALID_PROFILE_PHOTO', 'No se pudo leer la imagen seleccionada.')
    if not data or len(data) > 2 * 1024 * 1024:
        raise _problem(413, 'PROFILE_PHOTO_SIZE', 'La foto debe pesar máximo 2 MB.')
    valid_signature = (
        photo_mime == 'image/jpeg' and data.startswith(b'\xff\xd8\xff')
    ) or (
        photo_mime == 'image/png' and data.startswith(b'\x89PNG\r\n\x1a\n')
    )
    if not valid_signature:
        raise _problem(415, 'INVALID_PROFILE_PHOTO', 'Usa una imagen JPG o PNG válida.')
    return data, photo_mime


def _store_registration_photo(user_id: uuid.UUID,
                              photo: tuple[bytes, str] | None) -> str | None:
    if photo is None:
        return None
    data, mime = photo
    extension = 'jpg' if mime == 'image/jpeg' else 'png'
    return put_profile_photo(
        f'profile-photos/{user_id}/{uuid.uuid4()}.{extension}', data, mime)


def _cleanup_profile_photo(storage_key: str | None) -> None:
    if not storage_key:
        return
    try:
        delete_profile_photo(storage_key)
    except Exception:
        log.exception('Could not clean up profile photo after registration failed')


def _email_hash_code(code: str) -> str:
    return hashlib.sha256(f'{JWT_SECRET}:{code}'.encode()).hexdigest()


def _login_identifier_hash(identifier: str) -> str:
    normalized = identifier.strip().casefold()
    return hmac.new(JWT_SECRET.encode(), f'login:{normalized}'.encode(), hashlib.sha256).hexdigest()


def _take_member_lookup_attempt(cur, member_number: str) -> None:
    lookup_hash = _login_identifier_hash(f'member-lookup:{member_number.casefold()}')
    attempt = cur.execute("""INSERT INTO auth_login_limits
        (identifier_hash, attempt_count, window_started_at)
        VALUES (%s, 1, now())
        ON CONFLICT (identifier_hash) DO UPDATE SET
          attempt_count = CASE
            WHEN auth_login_limits.window_started_at < now() - interval '15 minutes' THEN 1
            ELSE auth_login_limits.attempt_count + 1 END,
          window_started_at = CASE
            WHEN auth_login_limits.window_started_at < now() - interval '15 minutes' THEN now()
            ELSE auth_login_limits.window_started_at END,
          blocked_until = CASE
            WHEN auth_login_limits.window_started_at < now() - interval '15 minutes' THEN NULL
            WHEN auth_login_limits.blocked_until > now() THEN auth_login_limits.blocked_until
            WHEN auth_login_limits.attempt_count + 1 >= 8 THEN now() + interval '15 minutes'
            ELSE NULL END
        RETURNING blocked_until""", (lookup_hash,)).fetchone()
    if attempt['blocked_until'] and attempt['blocked_until'] > datetime.now(UTC):
        raise _problem(429, 'MEMBER_LOOKUP_RATE_LIMIT',
                       'Demasiadas búsquedas para ese número. Intenta más tarde.')


def _new_registration_email_code(cur, user_id: uuid.UUID) -> str:
    # Serialize sends for an account so concurrent requests cannot bypass the
    # hourly delivery limit.
    cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))', (str(user_id),))
    cur.execute("DELETE FROM registration_email_codes WHERE created_at < now() - interval '2 days'")
    recent = cur.execute("""SELECT count(*) AS n FROM registration_email_codes
        WHERE user_id = %s AND created_at > now() - interval '1 hour'""",
        (user_id,)).fetchone()['n']
    if recent >= 3:
        raise _problem(429, 'EMAIL_CODE_RATE_LIMIT',
                       'Ya solicitaste varios códigos. Intenta de nuevo más tarde.')
    cur.execute("""UPDATE registration_email_codes SET consumed_at = now()
        WHERE user_id = %s AND consumed_at IS NULL""", (user_id,))
    code = f'{secrets.randbelow(1_000_000):06d}'
    cur.execute("""INSERT INTO registration_email_codes
        (user_id, code_hash, expires_at) VALUES (%s, %s, now() + interval '10 minutes')""",
        (user_id, _email_hash_code(code)))
    return code


def _deliver_registration_email_code(email: str, code: str) -> bool:
    try:
        _deliver_auth_code(email, code, 'registration')
        return True
    except RuntimeError:
        log.warning('Registration email verification is waiting for email provider configuration')
        return False


@app.post('/api/v1/auth/register/verify-email')
def verify_registration_email(payload: RegistrationEmailCodeRequest) -> dict:
    invalid = False
    response = None
    with pool.connection() as conn:
        with conn.cursor() as cur:
            user = cur.execute("""SELECT * FROM users WHERE gym_id = %s AND email = %s
                FOR UPDATE""", (GYM_ID, str(payload.email).lower())).fetchone()
            if user is None or user['email_verified']:
                invalid = True
            else:
                code_row = cur.execute("""SELECT id, code_hash, attempts
                    FROM registration_email_codes WHERE user_id = %s
                      AND consumed_at IS NULL AND expires_at > now()
                    ORDER BY created_at DESC LIMIT 1 FOR UPDATE""", (user['id'],)).fetchone()
                if code_row is None or code_row['attempts'] >= 5:
                    invalid = True
                elif not secrets.compare_digest(code_row['code_hash'], _email_hash_code(payload.code)):
                    cur.execute("""UPDATE registration_email_codes
                        SET attempts = attempts + 1,
                            consumed_at = CASE WHEN attempts + 1 >= 5 THEN now() ELSE consumed_at END
                        WHERE id = %s""", (code_row['id'],))
                    invalid = True
                else:
                    cur.execute('UPDATE registration_email_codes SET consumed_at = now() WHERE id = %s',
                                (code_row['id'],))
                    user = cur.execute("""UPDATE users SET email_verified = true, updated_at = now()
                        WHERE id = %s RETURNING *""", (user['id'],)).fetchone()
                    response = _session_response(cur, user)
    if invalid:
        raise _problem(400, 'INVALID_EMAIL_CODE', 'El código es incorrecto o ya venció.')
    return response


@app.post('/api/v1/auth/register/resend-code', status_code=202)
def resend_registration_email_code(payload: RegistrationEmailResendRequest) -> dict:
    email = str(payload.email).lower()
    code = None
    user_id = None
    with pool.connection() as conn:
        with conn.cursor() as cur:
            user = cur.execute("""SELECT id FROM users WHERE gym_id = %s AND email = %s
                AND email_verified = false FOR UPDATE""", (GYM_ID, email)).fetchone()
            if user:
                user_id = user['id']
                code = _new_registration_email_code(cur, user_id)
    if code and user_id:
        _deliver_registration_email_code(email, code)
    return {'status': 'accepted',
            'message': 'Si la cuenta requiere verificación, enviaremos un código al correo.'}


def _refresh_hash(token: str) -> str:
    return hashlib.sha256(f'{JWT_SECRET}:refresh:{token}'.encode()).hexdigest()


def _token_for(user: dict, sid: uuid.UUID, expires: datetime) -> str:
    return jwt.encode({
        'sub': str(user['id']), 'sid': str(sid), 'ver': user['session_version'],
        'iat': datetime.now(UTC), 'exp': expires,
    }, JWT_SECRET, algorithm=JWT_ALGORITHM)


def _session_response(cur, user: dict) -> dict:
    sid = uuid.uuid4()
    now = datetime.now(UTC)
    expires = now + timedelta(minutes=ACCESS_TOKEN_MINUTES)
    refresh_token = secrets.token_urlsafe(48)
    refresh_expires = now + timedelta(days=REFRESH_TOKEN_DAYS)
    cur.execute(
        """INSERT INTO auth_sessions
           (id, user_id, session_version, expires_at, refresh_token_hash, refresh_expires_at)
           VALUES (%s, %s, %s, %s, %s, %s)""",
        (sid, user['id'], user['session_version'], expires, _refresh_hash(refresh_token), refresh_expires))
    return {
        'access_token': _token_for(user, sid, expires),
        'refresh_token': refresh_token,
        'token_type': 'Bearer',
        'expires_at': expires.isoformat(),
        'user': _public_user(user),
    }


def _public_user(user: dict) -> dict:
    return {
        'id': str(user['id']), 'role': user['role'], 'status': user['status'],
        'first_name': user['first_name'], 'last_name': user['last_name'],
        'email': user['email'], 'member_number': user['member_number'],
        'status_reason': user['status_reason'],
        'deactivation_reason': user.get('deactivation_reason'),
        'deactivated_at': user['deactivated_at'].isoformat() if user['deactivated_at'] else None,
        'deactivated_by': user.get('deactivated_by_name'),
        'reactivation_until': user['reactivation_until'].isoformat() if user['reactivation_until'] else None,
    }


def _find_user(cur, identifier: str) -> dict | None:
    return cur.execute(
        """SELECT u.*, concat_ws(' ', a.first_name, a.last_name) AS deactivated_by_name
           FROM users u LEFT JOIN users a ON a.id = u.deactivated_by
           WHERE u.gym_id = %s AND (u.email = lower(%s) OR upper(u.member_number) = upper(%s))
           LIMIT 1""",
        (GYM_ID, identifier.strip(), identifier.strip())).fetchone()


def _find_login_candidates(cur, identifier: str) -> list[dict]:
    return cur.execute(
        """SELECT u.*, concat_ws(' ', a.first_name, a.last_name) AS deactivated_by_name
           FROM users u LEFT JOIN users a ON a.id = u.deactivated_by
           WHERE u.gym_id = %s AND (u.email = lower(%s) OR upper(u.member_number) = upper(%s))
           ORDER BY (u.email = lower(%s)) DESC, u.created_at""",
        (GYM_ID, identifier.strip(), identifier.strip(), identifier.strip())).fetchall()


def _normalize_person_name(value: str, label: str) -> str:
    normalized = ' '.join(value.split()).title()
    if not normalized or not any(character.isalpha() for character in normalized):
        raise _problem(422, 'INVALID_PERSON_NAME', f'Escribe un {label} válido.')
    return normalized


def _ensure_unique_person_name(cur, gym_id: uuid.UUID, first_name: str,
                               last_name: str,
                               exclude_user_id: uuid.UUID | None = None,
                               birth_date: date | None = None,
                               role: str | None = None) -> None:
    normalized_name = f'{first_name} {last_name}'.casefold()
    # For clients, a name alone is not a reliable identity: two different
    # people (including partners) can share it. Use the name and DOB together.
    # The transaction-scoped advisory lock makes the check safe against two
    # simultaneous registrations of the same person.
    identity = (f'{normalized_name}:{birth_date.isoformat()}'
                if role == 'client' and birth_date else normalized_name)
    cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))',
                (f'muskl-person-identity:{gym_id}:{identity}',))
    if role == 'client' and birth_date:
        existing = cur.execute("""SELECT u.id FROM users u
            JOIN client_profiles cp ON cp.user_id = u.id
            WHERE u.gym_id = %s AND u.role = 'client'
              AND u.status <> 'deactivated'
              AND lower(trim(regexp_replace(u.first_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
              AND lower(trim(regexp_replace(u.last_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
              AND cp.birth_date = %s
              AND (%s::uuid IS NULL OR u.id <> %s)
            LIMIT 1""",
            (gym_id, first_name, last_name, birth_date, exclude_user_id,
             exclude_user_id)).fetchone()
    else:
        existing = cur.execute("""SELECT id FROM users
            WHERE gym_id = %s AND status <> 'deactivated'
              AND lower(trim(regexp_replace(first_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
              AND lower(trim(regexp_replace(last_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
              AND (%s::uuid IS NULL OR id <> %s)
            LIMIT 1""",
            (gym_id, first_name, last_name, exclude_user_id,
             exclude_user_id)).fetchone()
    if existing:
        raise _problem(409, 'PERSON_NAME_IN_USE',
                       'Ya existe una cuenta de esta persona (mismo nombre y fecha de nacimiento) en este gimnasio.'
                       if role == 'client' and birth_date else
                       'Ya existe una cuenta con ese nombre y apellido en este gimnasio.')


def _create_user(cur, *, role: str, status: str, first_name: str, last_name: str,
                 email: str, phone: str | None, password: str, member_number: str | None = None,
                 email_verified: bool = True,
                 birth_date: date | None = None) -> dict:
    _validate_strong_password(password)
    first_name = _normalize_person_name(first_name, 'nombre')
    last_name = _normalize_person_name(last_name, 'apellido')
    _ensure_unique_person_name(cur, GYM_ID, first_name, last_name,
                               birth_date=birth_date, role=role)
    user_id = uuid.uuid4()
    return cur.execute(
        """INSERT INTO users
           (id, gym_id, role, status, first_name, last_name, email, phone, member_number, password_hash,
            email_verified)
           VALUES (%s, %s, %s::muskl_role, %s::account_status, %s, %s, %s, %s, %s, %s, %s)
           RETURNING *""",
        (user_id, GYM_ID, role, status, first_name, last_name, email.lower(),
         phone.strip() if phone else None, member_number, password_hasher.hash(password),
         email_verified)).fetchone()


def _notify_admins_of_staff_request(cur, gym_id: uuid.UUID, request_user: dict) -> None:
    admins = cur.execute("""SELECT id, admin_notification_preferences
        FROM users WHERE gym_id = %s AND role = 'admin' AND status = 'active'""",
        (gym_id,)).fetchall()
    role_name = 'entrenador' if request_user['role'] == 'trainer' else 'administrador'
    full_name = f"{request_user['first_name']} {request_user['last_name']}".strip()
    for admin in admins:
        preferences = admin['admin_notification_preferences'] or {}
        if preferences.get('new_requests', True):
            cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                VALUES (%s, 'staff_request', %s, %s, %s)""",
                (admin['id'], f'Nueva solicitud de {role_name}',
                 f'{full_name} · {request_user["email"]}',
                 Jsonb({'user_id': str(request_user['id']), 'role': request_user['role']})))


def _deliver_auth_code(email: str, code: str,
                       purpose: Literal['reset', 'change', 'email_change', 'registration']) -> str:
    if purpose == 'reset':
        subject = 'Código para restablecer tu contraseña de MUSKL'
        body = f'Tu código para restablecer la contraseña es {code}. Vence en 10 minutos.'
    elif purpose == 'change':
        subject = 'Código para cambiar tu contraseña de MUSKL'
        body = f'Tu código para cambiar la contraseña es {code}. Vence en 10 minutos.'
    elif purpose == 'email_change':
        subject = 'Verifica tu nuevo correo de MUSKL'
        body = f'Tu código para confirmar el cambio de correo es {code}. Vence en 10 minutos.'
    else:
        subject = 'Verifica tu correo de MUSKL'
        body = f'Tu código para verificar tu cuenta es {code}. Vence en 10 minutos.'
    email_provider_configured = (
        bool(os.getenv('MUSKL_SMTP_HOST'))
        or bool(os.getenv('BREVO_API_KEY') and os.getenv('BREVO_FROM_EMAIL'))
        or bool(os.getenv('MUSKL_RESEND_API_KEY') and os.getenv('MUSKL_RESEND_FROM'))
    )
    if email_provider_configured and _deliver_notice_email(email, subject, body):
        return 'email'
    if os.getenv('MUSKL_ENV', 'development') == 'development':
        log.info('DEV %s password code for %s: %s', purpose, email, code)
        return 'development'
    raise RuntimeError('No hay un canal disponible para enviar el código de seguridad.')


def _deliver_notice_email(email: str, subject: str, body: str) -> bool:
    """Send transactional mail over HTTPS when configured, with SMTP as fallback."""
    brevo_key = os.getenv('BREVO_API_KEY', '').strip()
    brevo_from = os.getenv('BREVO_FROM_EMAIL', '').strip()
    if brevo_key and brevo_from:
        sender = {'email': brevo_from}
        sender_name = os.getenv('BREVO_FROM_NAME', '').strip()
        if sender_name:
            sender['name'] = sender_name
        request = urllib.request.Request(
            'https://api.brevo.com/v3/smtp/email',
            data=json.dumps({
                'sender': sender,
                'to': [{'email': email}],
                'subject': subject,
                'textContent': body,
            }).encode(),
            headers={
                'api-key': brevo_key,
                'Content-Type': 'application/json',
                'Accept': 'application/json',
            },
            method='POST',
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                if 200 <= response.status < 300:
                    return True
        except Exception:
            log.exception('Could not send transactional email with Brevo to %s', email)

    resend_key = os.getenv('MUSKL_RESEND_API_KEY', '').strip()
    resend_from = os.getenv('MUSKL_RESEND_FROM', '').strip()
    if resend_key and resend_from:
        request = urllib.request.Request(
            'https://api.resend.com/emails',
            data=json.dumps({
                'from': resend_from,
                'to': [email],
                'subject': subject,
                'text': body,
            }).encode(),
            headers={
                'Authorization': f'Bearer {resend_key}',
                'Content-Type': 'application/json',
            },
            method='POST',
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return 200 <= response.status < 300
        except Exception:
            log.exception('Could not send account notice with Resend to %s', email)
    host = os.getenv('MUSKL_SMTP_HOST')
    if not host:
        log.warning('SMTP is not configured; account notice email was not sent to %s', email)
        return False
    message = EmailMessage()
    message['Subject'] = subject
    message['From'] = os.environ['MUSKL_SMTP_FROM']
    message['To'] = email
    message.set_content(body)
    port = int(os.getenv('MUSKL_SMTP_PORT', '587'))
    try:
        with smtplib.SMTP(host, port, timeout=15) as server:
            if os.getenv('MUSKL_SMTP_STARTTLS', 'true').lower() == 'true':
                server.starttls()
            if os.getenv('MUSKL_SMTP_USER'):
                server.login(os.environ['MUSKL_SMTP_USER'], os.environ['MUSKL_SMTP_PASSWORD'])
            server.send_message(message)
        return True
    except Exception:
        log.exception('Could not send account notice email to %s', email)
        return False


def _deliver_account_notice(email: str | None, subject: str, body: str) -> str | None:
    """Send account notices by email; SMS is intentionally not configured."""
    if email and _deliver_notice_email(email, subject, body):
        return 'email'
    log.warning('Account notice could not be delivered by email')
    return None


@app.get('/health')
def health() -> dict:
    with pool.connection() as conn:
        conn.execute('SELECT 1')
    return {'status': 'ok', 'service': 'muskl-api'}


@app.post('/api/v1/auth/login')
def login(payload: LoginRequest) -> dict:
    identifier = payload.identifier.strip()
    password = payload.password
    identifier_hash = _login_identifier_hash(identifier)
    response = None
    blocked = False
    invalid_credentials = False
    unverified_email = False
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM auth_login_limits WHERE window_started_at < now() - interval '1 day'")
            attempt = cur.execute("""INSERT INTO auth_login_limits
                    (identifier_hash, attempt_count, window_started_at)
                VALUES (%s, 1, now())
                ON CONFLICT (identifier_hash) DO UPDATE SET
                    attempt_count = CASE
                      WHEN auth_login_limits.window_started_at < now() - interval '15 minutes' THEN 1
                      WHEN auth_login_limits.blocked_until > now() THEN auth_login_limits.attempt_count
                      ELSE auth_login_limits.attempt_count + 1 END,
                    window_started_at = CASE
                      WHEN auth_login_limits.window_started_at < now() - interval '15 minutes' THEN now()
                      ELSE auth_login_limits.window_started_at END,
                    blocked_until = CASE
                      WHEN auth_login_limits.window_started_at < now() - interval '15 minutes' THEN NULL
                      WHEN auth_login_limits.blocked_until > now() THEN auth_login_limits.blocked_until
                      WHEN auth_login_limits.attempt_count + 1 >= 8 THEN now() + interval '15 minutes'
                      ELSE NULL END
                RETURNING attempt_count, blocked_until""", (identifier_hash,)).fetchone()
            blocked = attempt['blocked_until'] is not None and attempt['blocked_until'] > datetime.now(UTC)
            if not blocked:
                candidates = _find_login_candidates(cur, identifier)
                user = None
                for candidate in candidates:
                    try:
                        if password_hasher.verify(candidate['password_hash'], password):
                            user = candidate
                            break
                    except (VerifyMismatchError, VerificationError, InvalidHashError):
                        continue
                if user is None:
                    if not candidates:
                        try:
                            password_hasher.verify(DUMMY_PASSWORD_HASH, password)
                        except (VerifyMismatchError, VerificationError, InvalidHashError):
                            pass
                    # Keep unknown accounts and incorrect passwords indistinguishable.
                    invalid_credentials = True
                else:
                    if not user.get('email_verified', True):
                        unverified_email = True
                    else:
                        cur.execute('DELETE FROM auth_login_limits WHERE identifier_hash = %s',
                                    (identifier_hash,))
                        response = ({'user': _public_user(user)} if user['status'] == 'deactivated'
                                    else _session_response(cur, user))
    if blocked:
        raise _problem(429, 'LOGIN_RATE_LIMIT',
                       'Demasiados intentos. Espera 15 minutos antes de volver a intentarlo.')
    if invalid_credentials:
        raise _problem(401, 'INVALID_CREDENTIALS', 'Correo o contraseña incorrectos.')
    if unverified_email:
        raise _problem(403, 'EMAIL_NOT_VERIFIED',
                       'Verifica tu correo antes de iniciar sesión. Puedes solicitar otro código desde el registro.')
    return response


def _google_identity(identity_token: str) -> tuple[str, str, bool]:
    allowed_audiences = {
        value.strip()
        for value in os.getenv(
            'GOOGLE_OAUTH_CLIENT_IDS',
            '355323290179-5t96b3a4efp9lqju4dvt4hk3vu11m1m4.apps.googleusercontent.com',
        ).split(',')
        if value.strip()
    }
    if not allowed_audiences:
        raise _problem(503, 'GOOGLE_LOGIN_NOT_CONFIGURED',
                       'El acceso con Google todavía no está configurado en el servicio.')
    request = urllib.request.Request(
        'https://oauth2.googleapis.com/tokeninfo?' + urlencode({'id_token': identity_token}),
        headers={'Accept': 'application/json'},
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            claims = json.loads(response.read())
    except Exception:
        raise _problem(401, 'INVALID_SOCIAL_TOKEN',
                       'Google no pudo verificar esta sesión. Intenta de nuevo.')
    audience = claims.get('aud')
    issuer = claims.get('iss')
    if (audience not in allowed_audiences
            or issuer not in ('accounts.google.com', 'https://accounts.google.com')
            or int(claims.get('exp', 0)) <= int(datetime.now(UTC).timestamp())
            or claims.get('email_verified') not in (True, 'true')):
        raise _problem(401, 'INVALID_SOCIAL_TOKEN',
                       'La identidad de Google no es válida para MUSKL.')
    subject = str(claims.get('sub') or '')
    email = str(claims.get('email') or '').strip().lower()
    if not subject or not email:
        raise _problem(401, 'INVALID_SOCIAL_TOKEN',
                       'Google no entregó un correo verificado.')
    return subject, email, True


def _apple_identity(authorization_code: str) -> tuple[str, str | None, bool]:
    team_id = os.getenv('APPLE_TEAM_ID', '').strip()
    key_id = os.getenv('APPLE_KEY_ID', '').strip()
    service_id = os.getenv('APPLE_SERVICE_ID', '').strip()
    redirect_uri = os.getenv('APPLE_REDIRECT_URI', '').strip()
    private_key = os.getenv('APPLE_PRIVATE_KEY', '').replace('\\n', '\n').strip()
    if not all((team_id, key_id, service_id, redirect_uri, private_key)):
        raise _problem(503, 'APPLE_LOGIN_NOT_CONFIGURED',
                       'El acceso con Apple todavía no está configurado en el servicio.')
    now = datetime.now(UTC)
    client_secret = jwt.encode(
        {'iss': team_id, 'iat': now, 'exp': now + timedelta(minutes=5),
         'aud': 'https://appleid.apple.com', 'sub': service_id},
        private_key, algorithm='ES256', headers={'kid': key_id})
    body = urlencode({
        'client_id': service_id,
        'client_secret': client_secret,
        'code': authorization_code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirect_uri,
    }).encode()
    request = urllib.request.Request(
        'https://appleid.apple.com/auth/token', data=body,
        headers={'Content-Type': 'application/x-www-form-urlencoded',
                 'Accept': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            token_response = json.loads(response.read())
        identity_token = token_response['id_token']
        signing_key = jwt.PyJWKClient('https://appleid.apple.com/auth/keys').get_signing_key_from_jwt(
            identity_token).key
        claims = jwt.decode(
            identity_token, signing_key, algorithms=['RS256'],
            audience=service_id, issuer='https://appleid.apple.com',
            options={'require': ['exp', 'iat', 'sub', 'iss', 'aud']})
    except Exception:
        log.info('Apple authorization code could not be verified')
        raise _problem(401, 'INVALID_SOCIAL_TOKEN',
                       'Apple no pudo verificar esta sesión. Intenta de nuevo.')
    subject = str(claims.get('sub') or '')
    email = str(claims['email']).strip().lower() if claims.get('email') else None
    email_verified = claims.get('email_verified') in (True, 'true')
    if not subject:
        raise _problem(401, 'INVALID_SOCIAL_TOKEN',
                       'Apple no entregó una identidad válida.')
    return subject, email, email_verified


def _social_session(provider: str, subject: str, email: str | None,
                    email_verified: bool) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            identity = cur.execute(
                'SELECT user_id FROM social_identities WHERE provider = %s AND subject = %s FOR UPDATE',
                (provider, subject)).fetchone()
            if identity:
                user = cur.execute("""SELECT u.*, concat_ws(' ', a.first_name, a.last_name) AS deactivated_by_name
                    FROM users u LEFT JOIN users a ON a.id = u.deactivated_by
                    WHERE u.id = %s AND u.gym_id = %s FOR UPDATE OF u""",
                    (identity['user_id'], GYM_ID)).fetchone()
            elif email and email_verified:
                user = cur.execute("""SELECT u.*, concat_ws(' ', a.first_name, a.last_name) AS deactivated_by_name
                    FROM users u LEFT JOIN users a ON a.id = u.deactivated_by
                    WHERE u.gym_id = %s AND lower(u.email) = %s AND u.email_verified = true
                    FOR UPDATE OF u""", (GYM_ID, email)).fetchone()
                if user is not None:
                    cur.execute("""INSERT INTO social_identities (provider, subject, user_id)
                        VALUES (%s, %s, %s) ON CONFLICT (provider, subject) DO NOTHING""",
                        (provider, subject, user['id']))
                    linked = cur.execute(
                        'SELECT user_id FROM social_identities WHERE provider = %s AND subject = %s',
                        (provider, subject)).fetchone()
                    if linked is None or linked['user_id'] != user['id']:
                        raise _problem(409, 'SOCIAL_IDENTITY_LINKED',
                                       'Esta cuenta de proveedor ya está vinculada a otro perfil MUSKL.')
            else:
                user = None
            if user is None:
                raise _problem(404, 'SOCIAL_ACCOUNT_NOT_FOUND',
                               'No encontramos una cuenta MUSKL con este correo. Regístrate primero y vuelve a intentarlo.')
            if user['status'] == 'deactivated':
                raise _problem(403, 'ACCOUNT_DEACTIVATED',
                               'Esta cuenta está desactivada. Contacta al gimnasio para reactivarla.')
            if not user.get('email_verified', True):
                raise _problem(403, 'EMAIL_NOT_VERIFIED',
                               'Verifica el correo de tu cuenta MUSKL antes de continuar.')
            return _session_response(cur, user)


@app.post('/api/v1/auth/social/{provider}')
def social_login(provider: Literal['google', 'apple'], payload: SocialLoginRequest) -> dict:
    if provider == 'google':
        if not payload.identity_token:
            raise _problem(422, 'SOCIAL_TOKEN_REQUIRED',
                           'No recibimos el token de Google.')
        subject, email, email_verified = _google_identity(payload.identity_token)
    else:
        if not payload.authorization_code:
            raise _problem(422, 'SOCIAL_TOKEN_REQUIRED',
                           'No recibimos el código de Apple.')
        subject, email, email_verified = _apple_identity(payload.authorization_code)
    return _social_session(provider, subject, email, email_verified)


@app.post('/api/v1/auth/social/google/register-client', status_code=201)
def register_google_client(payload: GoogleClientRegistration) -> dict:
    subject, email, email_verified = _google_identity(payload.identity_token)
    if not email_verified:
        raise _problem(401, 'INVALID_SOCIAL_TOKEN',
                       'Google debe confirmar el correo antes del registro.')

    member_number = ' '.join(payload.member_number.split()).upper()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            existing = cur.execute(
                'SELECT id FROM users WHERE gym_id = %s AND lower(email) = %s FOR UPDATE',
                (GYM_ID, email)).fetchone()
            if existing:
                raise _problem(409, 'SOCIAL_EMAIL_IN_USE',
                               'Ese correo ya tiene una cuenta. Inicia sesión con Google.')

            _take_member_lookup_attempt(cur, member_number)
            registry = None
            if payload.member_registry_id:
                registry = cur.execute("""SELECT id, member_number, first_name,
                        last_name, birth_date, phone, payment_due_on, linked_user_id
                    FROM client_member_registry WHERE id = %s AND gym_id = %s
                      AND upper(trim(regexp_replace(member_number, '[[:space:]]+', ' ', 'g'))) = %s
                    FOR UPDATE""",
                    (payload.member_registry_id, GYM_ID, member_number)).fetchone()
                if registry is None:
                    raise _problem(409, 'MEMBER_RECORD_MISMATCH',
                                   'La ficha seleccionada no corresponde a ese número de socio.')
            else:
                candidates = cur.execute("""SELECT id, member_number, first_name,
                        last_name, birth_date, phone, payment_due_on, linked_user_id
                    FROM client_member_registry WHERE gym_id = %s
                      AND upper(trim(regexp_replace(member_number, '[[:space:]]+', ' ', 'g'))) = %s
                    ORDER BY first_name, last_name FOR UPDATE""",
                    (GYM_ID, member_number)).fetchall()
                if len(candidates) > 1:
                    raise _problem(409, 'MEMBER_SELECTION_REQUIRED',
                                   'Selecciona tu ficha entre las personas que comparten ese número.')
                if candidates:
                    registry = candidates[0]

            if registry and registry['linked_user_id']:
                raise _problem(409, 'MEMBER_ALREADY_REGISTERED',
                               'Esta ficha ya tiene una cuenta MUSKL. Inicia sesión con Google.')

            first_name = _normalize_person_name(payload.first_name, 'nombre')
            last_name = _normalize_person_name(payload.last_name, 'apellido')
            birth_date = payload.birth_date
            if registry:
                same_name = (
                    ' '.join(first_name.split()).casefold() ==
                    ' '.join(registry['first_name'].split()).casefold() and
                    ' '.join(last_name.split()).casefold() ==
                    ' '.join(registry['last_name'].split()).casefold())
                if not same_name or birth_date != registry['birth_date']:
                    raise _problem(409, 'MEMBER_IDENTITY_MISMATCH',
                                   'El nombre, apellido y fecha de nacimiento deben coincidir con la ficha del socio.')

            if not registry:
                same_person = cur.execute("""SELECT member_number
                    FROM client_member_registry WHERE gym_id = %s
                      AND lower(trim(regexp_replace(first_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                      AND lower(trim(regexp_replace(last_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                      AND birth_date = %s LIMIT 1""",
                    (GYM_ID, first_name, last_name, birth_date)).fetchone()
                if same_person:
                    raise _problem(409, 'PERSON_NAME_IN_USE',
                                   'Ya existe una ficha con esos datos. Revisa tu número de socio.')

            user = _create_user(
                cur,
                role='client',
                status='active_no_onboarding',
                first_name=first_name,
                last_name=last_name,
                email=email,
                phone=payload.phone or (registry['phone'] if registry else None),
                password=f'Aa1!{secrets.token_urlsafe(32)}',
                member_number=member_number,
                email_verified=True,
                birth_date=birth_date,
            )
            cur.execute("""INSERT INTO social_identities (provider, subject, user_id)
                VALUES ('google', %s, %s)""", (subject, user['id']))
            if registry:
                registry_id = registry['id']
                cur.execute("""UPDATE client_member_registry
                    SET linked_user_id = %s, updated_at = now()
                    WHERE id = %s AND linked_user_id IS NULL""",
                    (user['id'], registry_id))
            else:
                payment_due_on = cur.execute(
                    "SELECT (now() AT TIME ZONE timezone)::date AS date FROM gyms WHERE id = %s",
                    (GYM_ID,)).fetchone()['date']
                registry_id = cur.execute("""INSERT INTO client_member_registry
                    (gym_id, member_number, first_name, last_name, birth_date,
                     phone, payment_due_on, linked_user_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id""",
                    (GYM_ID, member_number, user['first_name'], user['last_name'],
                     birth_date, user['phone'], payment_due_on, user['id'])).fetchone()['id']
            cur.execute("INSERT INTO client_profiles (user_id, birth_date, member_registry_id) VALUES (%s, %s, %s)",
                        (user['id'], birth_date, registry_id))
            group = cur.execute("""INSERT INTO client_groups (gym_id, member_number)
                VALUES (%s, %s) ON CONFLICT (member_number) DO UPDATE
                SET gym_id = EXCLUDED.gym_id RETURNING id""",
                (GYM_ID, member_number)).fetchone()
            current_members = cur.execute(
                'SELECT count(*) AS count FROM client_group_members WHERE group_id = %s',
                (group['id'],)).fetchone()['count']
            cur.execute("INSERT INTO client_group_members (group_id, user_id, is_primary) VALUES (%s, %s, %s)",
                        (group['id'], user['id'], current_members == 0))
            return _session_response(cur, user)


@app.post('/api/v1/auth/apple/callback')
async def apple_android_callback(request: Request) -> RedirectResponse:
    form = await request.form()
    params = {key: str(form.get(key, '')) for key in
              ('code', 'state', 'id_token', 'error', 'error_description')
              if form.get(key) is not None}
    if not params or not (params.get('code') or params.get('error')):
        raise _problem(400, 'APPLE_CALLBACK_INVALID',
                       'Apple no devolvió los datos esperados.')
    target = ('intent://callback?' + urlencode(params)
              + '#Intent;package=mx.muskl.muskl;scheme=signinwithapple;end')
    return RedirectResponse(target, status_code=303)


@app.post('/api/v1/auth/member-lookup')
def lookup_member_number(payload: MemberNumberLookup) -> dict:
    member_number = ' '.join(payload.member_number.split()).upper()
    if not member_number:
        raise _problem(422, 'INVALID_MEMBER_NUMBER', 'Escribe tu número de socio.')
    with pool.connection() as conn:
        with conn.cursor() as cur:
            _take_member_lookup_attempt(cur, member_number)
            rows = cur.execute("""SELECT id, member_number, first_name, last_name,
                    birth_date, phone, payment_due_on,
                    (linked_user_id IS NOT NULL) AS registered
                FROM client_member_registry
                WHERE gym_id = %s
                  AND upper(trim(regexp_replace(member_number, '[[:space:]]+', ' ', 'g'))) = %s
                ORDER BY first_name, last_name, birth_date""",
                (GYM_ID, member_number)).fetchall()
    return {'found': bool(rows), 'members': [
        {'registry_id': str(row['id']),
         'first_name': _normalize_person_name(row['first_name'], 'nombre'),
         'last_name': _normalize_person_name(row['last_name'], 'apellido'),
         'birth_date': row['birth_date'].isoformat(),
         'phone': row['phone'],
         'payment_due_on': row['payment_due_on'].isoformat() if row['payment_due_on'] else None,
         'registered': row['registered']}
        for row in rows]}


@app.post('/api/v1/auth/register/client', status_code=201)
def register_client(payload: ClientRegistration) -> dict:
    photo = _decode_profile_photo(payload.photo_data, payload.photo_mime)
    storage_key = None
    verification_code = None
    user_id = None
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                existing = cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                                       (GYM_ID, str(payload.email).lower())).fetchone()
                if existing:
                    raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado.')
                member_number = ' '.join(payload.member_number.split()).upper()
                _take_member_lookup_attempt(cur, member_number)

                registry = None
                if payload.member_registry_id:
                    registry = cur.execute("""SELECT id, member_number, first_name, last_name,
                            birth_date, phone, payment_due_on, linked_user_id
                        FROM client_member_registry WHERE id = %s AND gym_id = %s
                          AND upper(trim(regexp_replace(member_number, '[[:space:]]+', ' ', 'g'))) = %s FOR UPDATE""",
                        (payload.member_registry_id, GYM_ID, member_number)).fetchone()
                    if registry is None:
                        raise _problem(409, 'MEMBER_RECORD_MISMATCH',
                                       'El registro de socio no corresponde a ese número.')
                else:
                    candidates = cur.execute("""SELECT id, member_number, first_name, last_name,
                            birth_date, phone, payment_due_on, linked_user_id
                        FROM client_member_registry WHERE gym_id = %s
                          AND upper(trim(regexp_replace(member_number, '[[:space:]]+', ' ', 'g'))) = %s
                        ORDER BY first_name, last_name FOR UPDATE""",
…30754 tokens truncated…) AT TIME ZONE g.timezone)::date
            )""", (client['gym_id'], client['id'])).fetchone()
        if membership is None:
            raise _problem(403, 'ACTIVE_MEMBERSHIP_REQUIRED',
                           'Necesitas una membresía activa para registrar asistencia.')
        attendance = conn.execute("""INSERT INTO attendance
                (gym_id, client_id, local_date, source)
            VALUES (%s, %s, %s, 'app')
            ON CONFLICT (client_id, local_date) DO NOTHING
            RETURNING local_date, checked_in_at, source""",
            (client['gym_id'], client['id'], membership['today'])).fetchone()
        created = attendance is not None
        if attendance is None:
            attendance = conn.execute("""SELECT local_date, checked_in_at, source
                FROM attendance WHERE client_id = %s AND local_date = %s""",
                (client['id'], membership['today'])).fetchone()
    return {
        'created': created,
        'date': attendance['local_date'].isoformat(),
        'checked_in_at': attendance['checked_in_at'].isoformat(),
        'source': attendance['source'],
    }


def _next_due_routine_session(cur, client_id: uuid.UUID, phase_id: uuid.UUID,
                              started_on: date, today: date) -> dict | None:
    # A missed session rolls forward within the current gym week. On Monday,
    # last week's unfinished sessions expire instead of accumulating forever.
    week_start = today - timedelta(days=today.isoweekday() - 1)
    return cur.execute("""SELECT dates.d::date AS scheduled_for_date,
                extract(isodow FROM dates.d)::integer AS day_number
            FROM generate_series(GREATEST(%s::date, %s::date), %s::date,
                                 interval '1 day') AS dates(d)
            WHERE EXISTS (SELECT 1 FROM routine_exercises re
                WHERE re.phase_id = %s
                  AND re.day_number = extract(isodow FROM dates.d)::integer)
              AND NOT EXISTS (SELECT 1 FROM workout_completions wc
                WHERE wc.phase_id = %s AND wc.client_id = %s
                  AND wc.scheduled_for_date = dates.d::date)
            ORDER BY dates.d LIMIT 1""",
        (started_on, week_start, today, phase_id, phase_id, client_id)).fetchone()


@app.get('/api/v1/client/routine')
def client_routine(day: int = Query(ge=1, le=7), client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
        _advance_due_client_phase(conn, client['id'])
        assignment = conn.execute("""SELECT cra.id AS assignment_id, cra.current_phase_id, cra.phase_started_at,
                (cra.phase_started_at AT TIME ZONE g.timezone)::date AS started_on,
                r.id AS routine_id, r.name AS routine_name, r.goal, r.days_per_week,
                rp.phase_number, rp.name AS phase_name, rp.status AS phase_status
            FROM client_routine_assignments cra JOIN routines r ON r.id = cra.routine_id
            JOIN gyms g ON g.id = r.gym_id
            JOIN routine_phases rp ON rp.id = cra.current_phase_id AND rp.status = 'published'
            WHERE cra.client_id = %s AND cra.ended_at IS NULL AND r.active LIMIT 1""",
            (client['id'],)).fetchone()
        if assignment is None:
            return {'assigned': False, 'exercises': []}
        today = conn.execute("SELECT (now() AT TIME ZONE timezone)::date AS d FROM gyms WHERE id = %s", (client['gym_id'],)).fetchone()['d']
        display_day = day
        due_session = None
        completed = None
        if day == today.isoweekday():
            completed = conn.execute("""SELECT id, scheduled_day_number, scheduled_for_date
                FROM workout_completions WHERE client_id = %s AND phase_id = %s AND workout_date = %s""",
                (client['id'], assignment['current_phase_id'], today)).fetchone()
            if completed:
                display_day = completed['scheduled_day_number']
            else:
                with conn.cursor() as cur:
                    due_session = _next_due_routine_session(
                        cur, client['id'], assignment['current_phase_id'],
                        assignment['started_on'], today)
                if due_session:
                    display_day = due_session['day_number']
        exercises = conn.execute("""SELECT re.id, re.day_number, re.position, re.name, re.sets,
                re.reps, re.rest_seconds, COALESCE(re.instructions, ec.instructions) AS instructions,
                COALESCE(ec.media_url, re.media_url) AS media_url, ec.muscle_group, re.media_key
            FROM routine_exercises re
            LEFT JOIN exercise_catalog ec ON ec.id = re.exercise_catalog_id
            WHERE re.phase_id = %s AND re.day_number = %s ORDER BY re.position""",
            (assignment['current_phase_id'], display_day)).fetchall()
        completed_exercises = conn.execute("""SELECT c.exercise_id
            FROM workout_exercise_completions c
            JOIN routine_exercises re ON re.id = c.exercise_id
            WHERE c.client_id = %s AND c.phase_id = %s AND c.workout_date = %s
              AND c.sets_completed >= re.sets""",
            (client['id'], assignment['current_phase_id'], today)).fetchall()
        set_progress = conn.execute("""SELECT exercise_id, sets_completed
            FROM workout_exercise_completions
            WHERE client_id = %s AND phase_id = %s AND workout_date = %s""",
            (client['id'], assignment['current_phase_id'], today)).fetchall()
    return {'assigned': True, 'routine_id': str(assignment['routine_id']), 'routine_name': assignment['routine_name'],
            'goal': assignment['goal'], 'days_per_week': assignment['days_per_week'],
            'phase_id': str(assignment['current_phase_id']), 'phase_number': assignment['phase_number'],
            'phase_name': assignment['phase_name'], 'phase_status': assignment['phase_status'],
            'scheduled_day_number': display_day,
            'scheduled_for_date': ((completed['scheduled_for_date'] if completed else due_session['scheduled_for_date']).isoformat()
                                   if (completed or due_session) else None),
            'today': today.isoformat(),
            'phase_started_at': assignment['phase_started_at'].isoformat(), 'completed_today': completed is not None,
            'can_complete_today': due_session is not None and completed is None,
            'completed_exercise_ids': [str(row['exercise_id']) for row in completed_exercises],
            'exercise_sets_completed': {str(row['exercise_id']): row['sets_completed'] for row in set_progress},
            'exercises': [{**exercise, 'id': str(exercise['id'])} for exercise in exercises]}


@app.post('/api/v1/client/routine/exercises/{exercise_id}/complete')
def complete_client_exercise(exercise_id: uuid.UUID, payload: WorkoutSetProgressRequest,
                             client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            assignment = cur.execute("""SELECT cra.current_phase_id,
                    (now() AT TIME ZONE g.timezone)::date AS today
                FROM client_routine_assignments cra
                JOIN gyms g ON g.id = %s
                WHERE cra.client_id = %s AND cra.ended_at IS NULL LIMIT 1""",
                (client['gym_id'], client['id'])).fetchone()
            if assignment is None:
                raise _problem(404, 'ROUTINE_NOT_ASSIGNED',
                               'Todavía no tienes una rutina asignada.')
            exercise = cur.execute("""SELECT id, sets FROM routine_exercises
                WHERE id = %s AND phase_id = %s""",
                (exercise_id, assignment['current_phase_id'])).fetchone()
            if exercise is None:
                raise _problem(404, 'EXERCISE_NOT_IN_ROUTINE',
                               'Este ejercicio no pertenece a tu rutina activa.')
            if payload.sets_completed > exercise['sets']:
                raise _problem(422, 'INVALID_SET_PROGRESS', 'La cantidad de series supera la indicada para el ejercicio.')
            if cur.execute("""SELECT 1 FROM workout_completions
                WHERE client_id = %s AND phase_id = %s AND workout_date = %s""",
                (client['id'], assignment['current_phase_id'], assignment['today'])).fetchone():
                raise _problem(409, 'WORKOUT_ALREADY_COMPLETED',
                               'La rutina de hoy ya fue completada.')
            saved = cur.execute("""INSERT INTO workout_exercise_completions
                    (client_id, phase_id, exercise_id, workout_date, sets_completed)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (client_id, phase_id, exercise_id, workout_date)
                DO UPDATE SET sets_completed = GREATEST(
                    workout_exercise_completions.sets_completed, EXCLUDED.sets_completed
                ), completed_at = now()
                RETURNING exercise_id, sets_completed""",
                (client['id'], assignment['current_phase_id'], exercise_id,
                 assignment['today'], payload.sets_completed)).fetchone()
    return {'exercise_id': str(exercise_id), 'sets_completed': saved['sets_completed'],
            'completed': saved['sets_completed'] >= exercise['sets'],
            'created': saved is not None}


@app.post('/api/v1/client/routine/complete', status_code=201)
def complete_client_workout(payload: WorkoutCompletionRequest,
                            client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            row = cur.execute("""SELECT cra.current_phase_id,
                    (cra.phase_started_at AT TIME ZONE g.timezone)::date AS started_on,
                    (now() AT TIME ZONE g.timezone)::date AS today
                FROM client_routine_assignments cra JOIN users u ON u.id = cra.client_id
                JOIN gyms g ON g.id = u.gym_id JOIN routine_phases rp ON rp.id = cra.current_phase_id AND rp.status = 'published'
                WHERE cra.client_id = %s AND cra.ended_at IS NULL LIMIT 1 FOR UPDATE OF cra""",
                (client['id'],)).fetchone()
            if row is None:
                raise _problem(404, 'ROUTINE_NOT_ASSIGNED', 'Todavía no tienes una rutina asignada.')
            due_session = _next_due_routine_session(
                cur, client['id'], row['current_phase_id'], row['started_on'], row['today'])
            if due_session is None:
                if payload.day_number is None:
                    raise _problem(409, 'NO_DUE_WORKOUT', 'Hoy no hay una rutina pendiente para finalizar.')
                has_exercises = cur.execute("""SELECT 1 FROM routine_exercises
                    WHERE phase_id = %s AND day_number = %s LIMIT 1""",
                    (row['current_phase_id'], payload.day_number)).fetchone()
                if has_exercises is None:
                    raise _problem(409, 'REST_DAY', 'Ese día no tiene ejercicios programados en tu rutina.')
                has_progress = cur.execute("""SELECT 1
                    FROM workout_exercise_completions c
                    JOIN routine_exercises re ON re.id = c.exercise_id
                    WHERE c.client_id = %s AND c.phase_id = %s
                      AND c.workout_date = %s AND c.sets_completed > 0
                      AND re.day_number = %s LIMIT 1""",
                    (client['id'], row['current_phase_id'], row['today'],
                     payload.day_number)).fetchone()
                if has_progress is None:
                    raise _problem(409, 'NO_DUE_WORKOUT', 'No hay progreso guardado para finalizar la rutina de ese día.')
                due_session = {
                    'scheduled_for_date': row['today'],
                    'day_number': payload.day_number,
                }
            scheduled_count = cur.execute("SELECT count(*) AS total FROM routine_exercises WHERE phase_id = %s AND day_number = %s",
                                          (row['current_phase_id'], due_session['day_number'])).fetchone()['total']
            if scheduled_count == 0:
                raise _problem(409, 'REST_DAY', 'Hoy no tienes ejercicios programados en tu rutina.')
            scheduled_ids = {exercise['id'] for exercise in cur.execute("""SELECT id
                FROM routine_exercises WHERE phase_id = %s AND day_number = %s""",
                (row['current_phase_id'], due_session['day_number'])).fetchall()}
            completed_ids = {exercise['exercise_id'] for exercise in cur.execute("""SELECT c.exercise_id
                FROM workout_exercise_completions c
                JOIN routine_exercises re ON re.id = c.exercise_id
                WHERE c.client_id = %s AND c.phase_id = %s AND c.workout_date = %s
                  AND c.sets_completed >= re.sets""",
                (client['id'], row['current_phase_id'], row['today'])).fetchall()}
            completed_today = completed_ids.intersection(scheduled_ids)
            fully_completed = completed_today == scheduled_ids
            completion = cur.execute("""INSERT INTO workout_completions
                    (client_id, phase_id, workout_date, duration_seconds,
                     scheduled_for_date, scheduled_day_number, is_fully_completed)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (client_id, phase_id, workout_date) DO NOTHING RETURNING id""",
                (client['id'], row['current_phase_id'], row['today'], payload.duration_seconds,
                 due_session['scheduled_for_date'], due_session['day_number'], fully_completed)).fetchone()
            if completion is None:
                raise _problem(409, 'ALREADY_COMPLETED', 'La rutina de hoy ya se marcó como completada.')
            cur.execute("""INSERT INTO attendance (gym_id, client_id, local_date, source)
                VALUES (%s, %s, %s, 'app')
                ON CONFLICT (client_id, local_date) DO NOTHING""",
                (client['gym_id'], client['id'], row['today']))
            trainer = cur.execute("""SELECT tca.trainer_id,
                    coalesce((tp.notification_preferences->>'client_activity')::boolean, true) AS enabled,
                    concat_ws(' ', c.first_name, c.last_name) AS client_name,
                    cra.routine_id
                FROM trainer_client_assignments tca
                JOIN trainer_profiles tp ON tp.user_id = tca.trainer_id
                JOIN users c ON c.id = tca.client_id
                LEFT JOIN client_routine_assignments cra ON cra.client_id = c.id AND cra.ended_at IS NULL
                WHERE tca.client_id = %s AND tca.ends_at IS NULL LIMIT 1""",
                (client['id'],)).fetchone()
            if trainer and trainer['enabled']:
                cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                    VALUES (%s, 'client_activity', 'Actividad de cliente', %s, %s)""",
                    (trainer['trainer_id'], f'{trainer["client_name"]} finalizó una sesión de su rutina.',
                     Jsonb({'client_id': str(client['id']), 'routine_id': str(trainer['routine_id']) if trainer['routine_id'] else None,
                            'completion_id': str(completion['id']),
                            'fully_completed': fully_completed})))
            activity = cur.execute("""SELECT
                    count(*) FILTER (WHERE workout_date >= date_trunc('week', %s::timestamp)::date) AS sessions_this_week,
                    count(*) AS sessions_total
                FROM workout_completions WHERE client_id = %s""",
                (row['today'], client['id'])).fetchone()
            return {'completed': True, 'date': row['today'].isoformat(),
            'exercise_count': len(completed_today), 'scheduled_exercise_count': scheduled_count,
            'fully_completed': fully_completed, 'duration_seconds': payload.duration_seconds,
            'sessions_this_week': activity['sessions_this_week'],
            'sessions_total': activity['sessions_total']}


@app.post('/api/v1/client/account-deletion-request', status_code=201)
def request_account_deletion(client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            existing = cur.execute("SELECT id FROM account_deletion_requests WHERE user_id = %s AND status = 'pending' FOR UPDATE",
                                   (client['id'],)).fetchone()
            if existing:
                raise _problem(409, 'DELETION_REQUEST_EXISTS', 'Ya tienes una solicitud de eliminación pendiente.')
            request = cur.execute("INSERT INTO account_deletion_requests (user_id) VALUES (%s) RETURNING id, requested_at",
                                  (client['id'],)).fetchone()
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type) VALUES (%s, %s, %s, %s)",
                        (client['gym_id'], client['id'], client['id'], 'account_deletion_requested'))
            cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                SELECT id, 'account_deletion_requested', 'Solicitud de baja recibida',
                    %s, %s FROM users
                WHERE gym_id = %s AND role = 'admin' AND status = 'active'""",
                (f"{client['first_name']} {client['last_name']} solicitó eliminar su cuenta.",
                 Jsonb({'request_id': str(request['id']), 'client_id': str(client['id'])}),
                 client['gym_id']))
    return {'id': str(request['id']), 'status': 'pending', 'requested_at': request['requested_at'].isoformat()}


@app.post('/api/v1/auth/logout', status_code=204)
def logout(user: dict = Depends(current_user), credentials: HTTPAuthorizationCredentials = Depends(bearer)) -> None:
    claims = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    with pool.connection() as conn:
        conn.execute('UPDATE auth_sessions SET revoked_at = now() WHERE id = %s AND user_id = %s',
                     (uuid.UUID(claims['sid']), user['id']))


@app.post('/api/v1/auth/password/reset-code', status_code=202)
def send_password_code(payload: PasswordCodeRequest) -> dict:
    code = f'{secrets.randbelow(1_000_000):06d}'
    email = str(payload.email).lower()
    should_deliver = False
    with pool.connection() as conn:
        with conn.cursor() as cur:
            user = cur.execute('SELECT id FROM users WHERE gym_id = %s AND email = %s',
                               (GYM_ID, email)).fetchone()
            if user:
                recent = cur.execute("SELECT count(*) AS n FROM password_reset_codes WHERE user_id = %s AND purpose = 'reset' AND created_at > now() - interval '1 hour'",
                                     (user['id'],)).fetchone()['n']
                if recent < 3:
                    cur.execute("""UPDATE password_reset_codes SET consumed_at = now()
                        WHERE user_id = %s AND purpose = 'reset' AND consumed_at IS NULL""",
                        (user['id'],))
                    cur.execute("INSERT INTO password_reset_codes (user_id, purpose, code_hash, expires_at) VALUES (%s, 'reset', %s, now() + interval '10 minutes')",
                                (user['id'], _email_hash_code(code)))
                    should_deliver = True
    if should_deliver:
        try:
            _deliver_auth_code(email, code, 'reset')
        except Exception:
            log.exception('Could not deliver password reset code')
            with pool.connection() as conn:
                conn.execute("""UPDATE password_reset_codes SET consumed_at = now()
                    WHERE code_hash = %s AND purpose = 'reset' AND consumed_at IS NULL""",
                    (_email_hash_code(code),))
    return {'message': 'Si el correo pertenece a una cuenta, recibirá un código de recuperación.'}


def _valid_reset_code(cur, email: str, code: str, *,
                      purpose: Literal['reset', 'change'] = 'reset',
                      consume: bool) -> bool:
    row = cur.execute(
        """SELECT c.id, c.user_id, c.code_hash, c.attempts
           FROM password_reset_codes c JOIN users u ON u.id = c.user_id
           WHERE u.gym_id = %s AND u.email = %s
             AND c.consumed_at IS NULL AND c.expires_at > now()
             AND c.attempts < 5 AND c.purpose = %s
           ORDER BY c.created_at DESC LIMIT 1 FOR UPDATE OF c""",
        (GYM_ID, email.lower(), purpose)).fetchone()
    if row is None:
        return False
    valid = secrets.compare_digest(row['code_hash'], _email_hash_code(code))
    if not valid:
        cur.execute('UPDATE password_reset_codes SET attempts = attempts + 1 WHERE id = %s', (row['id'],))
        return False
    if consume:
        cur.execute('UPDATE password_reset_codes SET consumed_at = now() WHERE id = %s', (row['id'],))
    return True


@app.post('/api/v1/auth/password/verify-code')
def verify_password_code(payload: VerifyCodeRequest) -> dict:
    with pool.connection() as conn:
        valid = _valid_reset_code(conn.cursor(), str(payload.email), payload.code, consume=False)
    if not valid:
        raise _problem(400, 'INVALID_CODE', 'El código es incorrecto o ya venció.')
    return {'valid': True}


@app.post('/api/v1/auth/password/reset')
def reset_password(payload: ResetPasswordRequest) -> dict:
    valid = False
    with pool.connection() as conn:
        with conn.cursor() as cur:
            user = cur.execute('SELECT id FROM users WHERE gym_id = %s AND email = %s FOR UPDATE',
                               (GYM_ID, str(payload.email).lower())).fetchone()
            if user:
                valid = _valid_reset_code(cur, str(payload.email), payload.code, consume=True)
                if valid:
                    cur.execute('UPDATE users SET password_hash = %s, session_version = session_version + 1, updated_at = now() WHERE id = %s',
                                (password_hasher.hash(payload.new_password), user['id']))
                    cur.execute('UPDATE auth_sessions SET revoked_at = now() WHERE user_id = %s AND revoked_at IS NULL',
                                (user['id'],))
                    cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type) VALUES (%s, %s, %s, 'password_reset')",
                                (GYM_ID, user['id'], user['id']))
    if not valid:
        raise _problem(400, 'INVALID_CODE', 'El código es incorrecto o ya venció.')
    with pool.connection() as conn:
        user = conn.execute('SELECT email FROM users WHERE id = %s',
                             (user['id'],)).fetchone()
    _deliver_account_notice(
        user['email'], 'Tu contraseña cambió · MUSKL',
        'La contraseña de tu cuenta MUSKL fue restablecida. Si no hiciste este cambio, contacta al gimnasio de inmediato.')
    return {'message': 'Contraseña actualizada. Inicia sesión con tu nueva contraseña.'}


@app.get('/api/v1/admin/gym')
def get_gym(admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        row = conn.execute('SELECT id, name, phone, address, opening_hours, timezone FROM gyms WHERE id = %s',
                           (admin['gym_id'],)).fetchone()
    return row


@app.get('/api/v1/admin/preferences')
def get_admin_preferences(admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        row = conn.execute("""SELECT admin_notification_preferences
            FROM users WHERE id = %s AND gym_id = %s""",
            (admin['id'], admin['gym_id'])).fetchone()
    return row['admin_notification_preferences']


@app.patch('/api/v1/admin/preferences')
def update_admin_preferences(payload: AdminPreferencesUpdate,
                             admin: dict = Depends(active_admin)) -> dict:
    preferences = {'new_requests': payload.new_requests}
    with pool.connection() as conn:
        conn.execute("""UPDATE users SET admin_notification_preferences = %s,
            updated_at = now() WHERE id = %s AND gym_id = %s""",
            (Jsonb(preferences), admin['id'], admin['gym_id']))
    return preferences


@app.get('/api/v1/admin/dashboard')
def admin_dashboard(admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        stats = conn.execute("""SELECT
            (SELECT count(*) FROM users WHERE gym_id = %s AND role = 'client' AND status <> 'deactivated') AS clients,
            (SELECT count(*) FROM users WHERE gym_id = %s AND role = 'trainer' AND status = 'active') AS trainers,
            (SELECT count(*) FROM routines r JOIN users t ON t.id = r.trainer_id
              WHERE r.gym_id = %s AND r.active) AS routines,
            (SELECT count(*) FROM users WHERE gym_id = %s AND role IN ('trainer', 'admin') AND status = 'pending') AS pending_requests,
            (SELECT count(*) FROM attendance a JOIN gyms g ON g.id = a.gym_id
              WHERE a.gym_id = %s AND a.local_date = (now() AT TIME ZONE g.timezone)::date) AS attendance_today""",
            (admin['gym_id'], admin['gym_id'], admin['gym_id'], admin['gym_id'], admin['gym_id'])).fetchone()
        window = conn.execute("SELECT (now() AT TIME ZONE timezone)::date AS today FROM gyms WHERE id = %s",
                              (admin['gym_id'],)).fetchone()['today']
        attendance = conn.execute("""SELECT local_date, count(*) AS total FROM attendance
            WHERE gym_id = %s AND local_date BETWEEN %s AND %s GROUP BY local_date ORDER BY local_date""",
            (admin['gym_id'], window - timedelta(days=6), window)).fetchall()
    return {**stats, 'attendance_week': [{'date': row['local_date'].isoformat(), 'total': row['total']} for row in attendance]}


@app.get('/api/v1/admin/users')
def admin_users(search: str = Query(default='', max_length=100),
                role: Literal['client', 'trainer', 'admin'] | None = None,
                status: Literal['active_no_onboarding', 'active', 'pending', 'rejected', 'deactivated'] | None = None,
                admin: dict = Depends(active_admin)) -> list[dict]:
    conditions = ['u.gym_id = %s']
    params: list = [admin['gym_id']]
    if role:
        conditions.append('u.role = %s::muskl_role')
        params.append(role)
    if status:
        conditions.append('u.status = %s::account_status')
        params.append(status)
    if search.strip():
        conditions.append("(concat_ws(' ', u.first_name, u.last_name) ILIKE %s OR u.email ILIKE %s OR upper(u.member_number) LIKE upper(%s))")
        term = f'%{search.strip()}%'
        params.extend([term, term, term])
    where = ' AND '.join(conditions)
    with pool.connection() as conn:
        rows = conn.execute(f"""SELECT u.id, u.role, u.status, u.first_name, u.last_name, u.email, u.phone,
                u.member_number, u.status_reason, u.deactivation_reason, u.deactivation_note,
                u.deactivated_at, u.reactivation_until,
                COALESCE(cp.trainer_reassignment_required, false) AS trainer_reassignment_required,
                concat_ws(' ', a.first_name, a.last_name) AS deactivated_by,
                p.name AS membership_plan, m.ends_on AS membership_ends_on, tp.specialty,
                (SELECT count(*) FROM trainer_client_assignments tca WHERE tca.trainer_id = u.id AND tca.ends_at IS NULL) AS assigned_clients,
                current_trainer.id AS trainer_id, current_trainer.name AS trainer_name
            FROM users u
            LEFT JOIN users a ON a.id = u.deactivated_by
            LEFT JOIN LATERAL (SELECT id, plan_id, ends_on FROM memberships
              WHERE client_id = u.id AND status = 'active' ORDER BY ends_on DESC LIMIT 1) m ON true
            LEFT JOIN membership_plans p ON p.id = m.plan_id
            LEFT JOIN trainer_profiles tp ON tp.user_id = u.id
            LEFT JOIN client_profiles cp ON cp.user_id = u.id
            LEFT JOIN LATERAL (
                SELECT t.id, concat_ws(' ', t.first_name, t.last_name) AS name
                FROM trainer_client_assignments tca
                JOIN users t ON t.id = tca.trainer_id AND t.status = 'active'
                WHERE tca.client_id = u.id AND tca.ends_at IS NULL
                LIMIT 1
            ) current_trainer ON true
            WHERE {where} ORDER BY u.created_at DESC LIMIT 500""", params).fetchall()
    return [{**row, 'id': str(row['id'])} for row in rows]


class GymUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=150)
    phone: str | None = Field(default=None, max_length=30)
    address: str | None = Field(default=None, max_length=300)
    timezone: str = 'America/Mexico_City'
    opening_hours: dict[str, str] = Field(default_factory=dict)


@app.patch('/api/v1/admin/gym')
def update_gym(payload: GymUpdate, admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        row = conn.execute('UPDATE gyms SET name = %s, phone = %s, address = %s, opening_hours = %s, timezone = %s, updated_at = now() WHERE id = %s RETURNING id, name, phone, address, opening_hours, timezone',
                           (payload.name, payload.phone, payload.address, Jsonb(payload.opening_hours), payload.timezone, admin['gym_id'])).fetchone()
        conn.execute('INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, %s, %s)',
                     (admin['gym_id'], admin['id'], 'gym_settings_updated', Jsonb({'name': payload.name})))
    return row


@app.get('/api/v1/admin/routines')
def admin_routines(search: str = Query(default='', max_length=100),
                   goal: Literal['Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza'] | None = None,
                   admin: dict = Depends(active_admin)) -> list[dict]:
    conditions = ['r.gym_id = %s', 'r.active']
    params: list = [admin['gym_id']]
    if goal:
        conditions.append('r.goal = %s')
        params.append(goal)
    if search.strip():
        conditions.append("(r.name ILIKE %s OR concat_ws(' ', u.first_name, u.last_name) ILIKE %s)")
        term = f'%{search.strip()}%'
        params.extend([term, term])
    with pool.connection() as conn:
        rows = conn.execute(f"""SELECT r.id, r.name, r.goal, r.days_per_week,
                concat_ws(' ', u.first_name, u.last_name) AS trainer_name,
                (SELECT count(*) FROM client_routine_assignments cra
                    WHERE cra.routine_id = r.id AND cra.ended_at IS NULL) AS assigned_clients,
                (SELECT count(*) FROM routine_phases rp WHERE rp.routine_id = r.id) AS phases,
                (SELECT max(rp.status::text) FROM routine_phases rp
                    WHERE rp.routine_id = r.id AND rp.phase_number = 1) AS phase_status
            FROM routines r JOIN users u ON u.id = r.trainer_id
            WHERE {' AND '.join(conditions)} ORDER BY r.updated_at DESC LIMIT 500""", params).fetchall()
    return [{**row, 'id': str(row['id'])} for row in rows]


@app.get('/api/v1/admin/routines/{routine_id}')
def admin_routine_detail(routine_id: uuid.UUID,
                         admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        routine = conn.execute("""SELECT r.id, r.name, r.goal, r.days_per_week,
                concat_ws(' ', u.first_name, u.last_name) AS trainer_name
            FROM routines r LEFT JOIN users u ON u.id = r.trainer_id
            WHERE r.id = %s AND r.gym_id = %s AND r.active""",
            (routine_id, admin['gym_id'])).fetchone()
        if routine is None:
            raise _problem(404, 'ROUTINE_NOT_FOUND', 'No encontramos esa rutina.')
        phases = conn.execute("""SELECT rp.id, rp.phase_number, rp.name, rp.duration_weeks,
                rp.status, rp.published_at,
                (SELECT count(*) FROM routine_exercises re WHERE re.phase_id = rp.id) AS exercise_count
            FROM routine_phases rp WHERE rp.routine_id = %s ORDER BY rp.phase_number""",
            (routine_id,)).fetchall()
        clients = conn.execute("""SELECT u.id, u.first_name, u.last_name, u.member_number,
                cra.current_phase_id FROM client_routine_assignments cra
            JOIN users u ON u.id = cra.client_id
            WHERE cra.routine_id = %s AND cra.ended_at IS NULL ORDER BY u.first_name, u.last_name""",
            (routine_id,)).fetchall()
        exercises = conn.execute("""SELECT re.id, re.phase_id, rp.phase_number,
                re.day_number, re.position, re.name, re.sets, re.reps, re.rest_seconds, re.instructions
            FROM routine_exercises re JOIN routine_phases rp ON rp.id = re.phase_id
            WHERE rp.routine_id = %s ORDER BY rp.phase_number, re.day_number, re.position""",
            (routine_id,)).fetchall()
    routine['id'] = str(routine['id'])
    for phase in phases:
        phase['id'] = str(phase['id'])
        phase['published_at'] = phase['published_at'].isoformat() if phase['published_at'] else None
    for client in clients:
        client['id'] = str(client['id'])
        client['current_phase_id'] = str(client['current_phase_id'])
    for exercise in exercises:
        exercise['id'] = str(exercise['id'])
        exercise['phase_id'] = str(exercise['phase_id'])
    return {**routine, 'phases': phases, 'clients': clients, 'exercises': exercises}


@app.post('/api/v1/admin/routines/{routine_id}/assign')
def assign_admin_routine(routine_id: uuid.UUID, payload: RoutineAssignmentRequest,
                         admin: dict = Depends(active_admin)) -> dict:
    """Let the gym administrator assign a published routine without a trainer."""
    with pool.connection() as conn:
        with conn.cursor() as cur:
            row = cur.execute("""SELECT r.id AS routine_id, rp.id AS phase_id,
                    u.id AS client_id
                FROM routines r
                JOIN routine_phases rp ON rp.routine_id = r.id
                JOIN users u ON u.id = %s AND u.gym_id = r.gym_id
                    AND u.role = 'client' AND u.status = 'active'
                WHERE r.id = %s AND r.gym_id = %s AND r.active
                    AND rp.id = %s AND rp.status = 'published'
                FOR UPDATE OF u""",
                (payload.client_id, routine_id, admin['gym_id'], payload.phase_id)).fetchone()
            if row is None:
                raise _problem(404, 'assignment_not_allowed',
                               'La rutina publicada o el socio activo no se encontró en este gimnasio.')
            cur.execute("""UPDATE client_routine_assignments SET ended_at = now()
                WHERE client_id = %s AND ended_at IS NULL""", (row['client_id'],))
            assignment = cur.execute("""INSERT INTO client_routine_assignments
                (client_id, routine_id, current_phase_id, assigned_by)
                VALUES (%s, %s, %s, %s) RETURNING id""",
                (row['client_id'], row['routine_id'], row['phase_id'], admin['id'])).fetchone()
            cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                VALUES (%s, 'routine_assigned', 'Tu rutina está lista', %s, %s)""",
                (row['client_id'],
                 'El administrador del gimnasio te asignó una rutina. Ya puedes consultarla en Inicio.',
                 Jsonb({'routine_id': str(row['routine_id'])})))
            cur.execute("""INSERT INTO account_audit_events
                (gym_id, actor_id, subject_id, event_type, details)
                VALUES (%s, %s, %s, 'routine_assigned_by_admin', %s)""",
                (admin['gym_id'], admin['id'], row['client_id'],
                 Jsonb({'routine_id': str(row['routine_id']),
                        'assignment_id': str(assignment['id'])})))
    return {'assignment_id': str(assignment['id']),
            'client_id': str(row['client_id']),
            'routine_id': str(row['routine_id'])}


@app.get('/api/v1/admin/membership-plans')
def get_plans(admin: dict = Depends(active_admin)) -> list[dict]:
    with pool.connection() as conn:
        return conn.execute('SELECT id, name, price_mxn, duration_days, min_group_size, max_group_size, active FROM membership_plans WHERE gym_id = %s ORDER BY name',
                            (admin['gym_id'],)).fetchall()


class PlanUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    price_mxn: float | None = Field(default=None, ge=0)
    duration_days: int | None = Field(default=None, gt=0, le=3650)
    min_group_size: int = Field(default=1, ge=1, le=50)
    max_group_size: int = Field(default=1, ge=1, le=50)
    active: bool = True

    @field_validator('max_group_size')
    @classmethod
    def validate_group_size(cls, value: int, info) -> int:
        if value < info.data.get('min_group_size', 1):
            raise ValueError('El máximo de personas no puede ser menor que el mínimo.')
        return value


@app.post('/api/v1/admin/membership-plans', status_code=201)
def create_plan(payload: PlanUpdate, admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        try:
            row = conn.execute("""INSERT INTO membership_plans
                (gym_id, name, price_mxn, duration_days, min_group_size, max_group_size, active)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id, name, price_mxn, duration_days, min_group_size, max_group_size, active""",
                (admin['gym_id'], payload.name.strip(), payload.price_mxn,
                 payload.duration_days, payload.min_group_size, payload.max_group_size,
                 payload.active)).fetchone()
        except Exception as exc:
            db_message = f'{exc} {getattr(getattr(exc, "diag", None), "constraint_name", "")}'
            if 'membership_plans_gym_id_name_key' in db_message:
                raise _problem(409, 'PLAN_NAME_IN_USE', 'Ya existe un plan con ese nombre.')
            raise
        conn.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, %s, %s)",
                     (admin['gym_id'], admin['id'], 'membership_plan_created', Jsonb({'name': payload.name})))
    return row


@app.put('/api/v1/admin/membership-plans/{plan_id}')
def update_plan(plan_id: uuid.UUID, payload: PlanUpdate, admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        try:
            row = conn.execute("""UPDATE membership_plans SET name = %s, price_mxn = %s,
                duration_days = %s, min_group_size = %s, max_group_size = %s, active = %s
                WHERE id = %s AND gym_id = %s
                RETURNING id, name, price_mxn, duration_days, min_group_size, max_group_size, active""",
                (payload.name.strip(), payload.price_mxn, payload.duration_days,
                 payload.min_group_size, payload.max_group_size, payload.active,
                 plan_id, admin['gym_id'])).fetchone()
        except Exception as exc:
            constraint = getattr(getattr(exc, 'diag', None), 'constraint_name', '')
            if constraint == 'membership_plans_gym_id_name_key':
                raise _problem(409, 'PLAN_NAME_IN_USE', 'Ya existe un plan con ese nombre.')
            raise
    if row is None:
        raise _problem(404, 'PLAN_NOT_FOUND', 'No encontramos ese plan.')
    return row


@app.post('/api/v1/admin/invite-codes', status_code=201)
def create_invite(admin: dict = Depends(active_admin)) -> dict:
    raw_token = f"MSK-ADM-{secrets.token_urlsafe(9).upper()}"
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    with pool.connection() as conn:
        row = conn.execute('INSERT INTO admin_invite_tokens (gym_id, token_hash, created_by, expires_at) VALUES (%s, %s, %s, now() + interval \'30 days\') RETURNING id, expires_at',
                           (admin['gym_id'], token_hash, admin['id'])).fetchone()
        conn.execute('INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, %s, %s)',
                     (admin['gym_id'], admin['id'], 'admin_invite_created', Jsonb({'invite_id': str(row['id'])})))
    return {'id': str(row['id']), 'token': raw_token, 'expires_at': row['expires_at'].isoformat()}


@app.get('/api/v1/admin/invite-codes')
def list_invites(admin: dict = Depends(active_admin)) -> list[dict]:
    with pool.connection() as conn:
        return conn.execute('SELECT id, label, expires_at, revoked_at, used_at, created_at FROM admin_invite_tokens WHERE gym_id = %s ORDER BY created_at DESC',
                            (admin['gym_id'],)).fetchall()


@app.delete('/api/v1/admin/invite-codes/{invite_id}', status_code=204)
def revoke_invite(invite_id: uuid.UUID, admin: dict = Depends(active_admin)) -> None:
    with pool.connection() as conn:
        result = conn.execute('UPDATE admin_invite_tokens SET revoked_at = now() WHERE id = %s AND gym_id = %s AND revoked_at IS NULL',
                              (invite_id, admin['gym_id']))
    if result.rowcount == 0:
        raise _problem(404, 'INVITE_NOT_FOUND', 'No encontramos un código activo con ese ID.')


@app.get('/api/v1/admin/staff-requests')
def staff_requests(admin: dict = Depends(active_admin)) -> list[dict]:
    with pool.connection() as conn:
        return conn.execute("""SELECT u.id, u.role, u.first_name, u.last_name, u.email, u.phone, u.created_at,
           tp.specialty,
           coalesce((SELECT jsonb_agg(jsonb_build_object('id', tc.id, 'title', tc.title)
               ORDER BY tc.created_at) FROM trainer_certifications tc
               WHERE tc.trainer_id = u.id), '[]'::jsonb) AS certifications
           FROM users u LEFT JOIN trainer_profiles tp ON tp.user_id = u.id
           WHERE u.gym_id = %s AND u.status = 'pending' AND u.role IN ('trainer', 'admin')
            ORDER BY u.created_at""", (admin['gym_id'],)).fetchall()


@app.get('/api/v1/admin/trainers/{trainer_id}/certifications/{certification_id}/download')
def admin_trainer_certification_download(
    trainer_id: uuid.UUID,
    certification_id: uuid.UUID,
    admin: dict = Depends(active_admin),
) -> dict:
    with pool.connection() as conn:
        certificate = conn.execute("""SELECT tc.storage_key FROM trainer_certifications tc
            JOIN users trainer ON trainer.id = tc.trainer_id
            WHERE tc.id = %s AND trainer.id = %s AND trainer.gym_id = %s
              AND trainer.role = 'trainer'""",
            (certification_id, trainer_id, admin['gym_id'])).fetchone()
    if certificate is None:
        raise _problem(404, 'CERTIFICATION_NOT_FOUND', 'No encontramos ese certificado.')
    if not certificate['storage_key'].startswith('r2://'):
        raise _problem(410, 'CERTIFICATION_NEEDS_MIGRATION',
                       'Este certificado aún no está en el almacenamiento privado. Migra o vuelve a subir el archivo.')
    try:
        url = presigned_certificate_url(certificate['storage_key'], expires_in=600)
    except StorageNotConfigured:
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', 'El almacenamiento privado no está disponible.')
    except StorageReadError:
        log.exception('Could not create private certificate link')
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', 'No se pudo generar el enlace temporal.')
    return {'url': url, 'expires_in': 600}


@app.get('/api/v1/admin/notifications')
def admin_notifications(admin: dict = Depends(active_admin)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT id, kind, title, body, payload, created_at
            FROM notifications WHERE user_id = %s AND kind IN ('staff_request', 'profile_updated', 'account_deletion_requested')
              AND read_at IS NULL ORDER BY created_at DESC LIMIT 20""",
            (admin['id'],)).fetchall()
    return [{**row, 'id': str(row['id']), 'created_at': row['created_at'].isoformat()}
            for row in rows]


@app.post('/api/v1/admin/notifications/{notification_id}/read', status_code=204)
def mark_admin_notification_read(notification_id: uuid.UUID,
                                admin: dict = Depends(active_admin)) -> None:
    with pool.connection() as conn:
        conn.execute("""UPDATE notifications SET read_at = now()
            WHERE id = %s AND user_id = %s AND kind IN ('staff_request', 'profile_updated', 'account_deletion_requested')
              AND read_at IS NULL""", (notification_id, admin['id']))


@app.post('/api/v1/admin/staff-requests/{user_id}/review')
def review_staff(user_id: uuid.UUID, payload: StaffReviewRequest,
                 admin: dict = Depends(active_admin)) -> dict:
    new_status = 'active' if payload.approved else 'rejected'
    with pool.connection() as conn:
        with conn.cursor() as cur:
            user = cur.execute("SELECT id, role, email FROM users WHERE id = %s AND gym_id = %s AND status = 'pending' AND role IN ('trainer', 'admin') FOR UPDATE",
                               (user_id, admin['gym_id'])).fetchone()
            if user is None:
                raise _problem(404, 'REQUEST_NOT_FOUND', 'La solicitud ya no está pendiente.')
            cur.execute('UPDATE users SET status = %s::account_status, status_reason = %s, rejected_at = %s, rejected_by = %s WHERE id = %s',
                        (new_status, None if payload.approved else payload.reason, None if payload.approved else datetime.now(UTC), None if payload.approved else admin['id'], user_id))
            cur.execute('INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type, details) VALUES (%s, %s, %s, %s, %s)',
                        (admin['gym_id'], admin['id'], user_id, 'staff_request_reviewed', Jsonb({'approved': payload.approved, 'reason': payload.reason})))
            cur.execute('INSERT INTO notifications (user_id, kind, title, body) VALUES (%s, %s, %s, %s)',
                        (user_id, 'staff_request', 'Solicitud revisada', 'El gimnasio revisó tu solicitud. Inicia sesión para ver el resultado.'))
    result = ('aprobada' if payload.approved else 'rechazada')
    reason = f"\nMotivo: {payload.reason}" if not payload.approved and payload.reason else ''
    _deliver_notice_email(user['email'], f'Solicitud de cuenta {result} · MUSKL',
        f'Tu solicitud de cuenta fue {result} por el gimnasio.{reason}\n\nInicia sesión en MUSKL para continuar.')
    return {'id': str(user_id), 'status': new_status}


@app.get('/api/v1/admin/account-deletion-requests')
def account_deletion_requests(admin: dict = Depends(active_admin)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT dr.id, dr.user_id, dr.status, dr.requested_at, dr.note,
                u.first_name, u.last_name, u.email, u.member_number
            FROM account_deletion_requests dr JOIN users u ON u.id = dr.user_id
            WHERE u.gym_id = %s AND dr.status = 'pending'
            ORDER BY dr.requested_at""", (admin['gym_id'],)).fetchall()
    return [{**row, 'id': str(row['id']), 'user_id': str(row['user_id']),
             'requested_at': row['requested_at'].isoformat()} for row in rows]


@app.post('/api/v1/admin/account-deletion-requests/{request_id}/review')
def review_account_deletion(request_id: uuid.UUID, payload: AccountDeletionReview,
                            admin: dict = Depends(active_admin)) -> dict:
    new_status = 'approved' if payload.approved else 'rejected'
    with pool.connection() as conn:
        with conn.cursor() as cur:
            request = cur.execute("""SELECT dr.id, dr.user_id, dr.status, u.status AS account_status,
                    u.role, u.email
                FROM account_deletion_requests dr JOIN users u ON u.id = dr.user_id
                WHERE dr.id = %s AND u.gym_id = %s FOR UPDATE OF dr, u""",
                (request_id, admin['gym_id'])).fetchone()
            if request is None or request['status'] != 'pending':
                raise _problem(404, 'DELETION_REQUEST_NOT_FOUND', 'La solicitud ya fue revisada o no existe.')
            if request['role'] != 'client':
                raise _problem(409, 'DELETION_REQUEST_INVALID', 'Esta solicitud no pertenece a una cuenta de cliente.')
            cur.execute("""UPDATE account_deletion_requests SET status = %s::request_status,
                resolved_at = now(), resolved_by = %s, note = %s WHERE id = %s""",
                (new_status, admin['id'], payload.note, request_id))
            if payload.approved:
                if request['account_status'] != 'deactivated':
                    cur.execute("""UPDATE users SET status = 'deactivated', status_reason = %s,
                        deactivation_reason = 'Solicitud del socio', deactivation_note = %s,
                        deactivated_at = now(), deactivated_by = %s WHERE id = %s""",
                        (payload.note or 'Baja aprobada por solicitud del socio.', payload.note,
                         admin['id'], request['user_id']))
                cur.execute("""UPDATE auth_sessions SET revoked_at = coalesce(revoked_at, now()),
                    refresh_expires_at = (SELECT reactivation_until FROM users WHERE id = %s)
                    WHERE user_id = %s""", (request['user_id'], request['user_id']))
            body = ('La solicitud de baja fue aprobada. El acceso a MUSKL quedó desactivado.'
                    if payload.approved else 'La solicitud de baja no fue aprobada. Tu cuenta sigue activa.')
            cur.execute("INSERT INTO notifications (user_id, kind, title, body, payload) VALUES (%s, 'account_deletion_reviewed', 'Solicitud de baja revisada', %s, %s)",
                (request['user_id'], body, Jsonb({'approved': payload.approved, 'note': payload.note})))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type, details) VALUES (%s, %s, %s, 'account_deletion_reviewed', %s)",
                (admin['gym_id'], admin['id'], request['user_id'], Jsonb({'approved': payload.approved, 'request_id': str(request_id), 'note': payload.note})))
    _deliver_notice_email(request['email'], 'Solicitud de baja revisada · MUSKL', body)
    return {'id': str(request_id), 'status': new_status}


@app.patch('/api/v1/admin/users/{user_id}/deactivate')
def deactivate_user(user_id: uuid.UUID, payload: DeactivationRequest,
                    admin: dict = Depends(active_admin)) -> dict:
    now = datetime.now(UTC)
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                user = cur.execute("SELECT id, role, status, email FROM users WHERE id = %s AND gym_id = %s FOR UPDATE",
                                   (user_id, admin['gym_id'])).fetchone()
                if user is None:
                    raise _problem(404, 'USER_NOT_FOUND', 'No encontramos ese usuario.')
                if user['role'] not in ('client', 'trainer'):
                    raise _problem(403, 'ROLE_CANNOT_BE_DEACTIVATED',
                                   'Desde esta acción solo se pueden dar de baja socios y entrenadores.')
                if user['status'] == 'deactivated':
                    raise _problem(409, 'ALREADY_DEACTIVATED', 'La cuenta ya está dada de baja.')
                if user['role'] == 'trainer':
                    # Preserve assignment history, but detach current clients so
                    # an admin can deactivate a trainer in one operation.
                    cur.execute("""UPDATE client_routine_assignments SET ended_at = now()
                        WHERE client_id IN (SELECT client_id FROM trainer_client_assignments
                            WHERE trainer_id = %s AND ends_at IS NULL)
                          AND ended_at IS NULL""", (user_id,))
                    cur.execute("""UPDATE client_profiles SET trainer_reassignment_required = true
                        WHERE user_id IN (SELECT client_id FROM trainer_client_assignments
                            WHERE trainer_id = %s AND ends_at IS NULL)""", (user_id,))
                    cur.execute("""UPDATE trainer_client_assignments
                        SET ends_at = now() WHERE trainer_id = %s AND ends_at IS NULL""",
                        (user_id,))
                    cur.execute("""UPDATE client_trainer_requests SET status = 'cancelled', reviewed_at = now()
                        WHERE trainer_id = %s AND status = 'pending'""", (user_id,))
                cur.execute("""UPDATE users SET status = 'deactivated', status_reason = %s,
                   deactivation_reason = %s, deactivation_note = %s, deactivated_at = %s,
                   deactivated_by = %s WHERE id = %s""",
                   (payload.note or payload.reason, payload.reason, payload.note, now, admin['id'], user_id))
                cur.execute("""UPDATE auth_sessions SET revoked_at = coalesce(revoked_at, now()),
                    refresh_expires_at = (SELECT reactivation_until FROM users WHERE id = %s)
                    WHERE user_id = %s""", (user_id, user_id))
                cur.execute('INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type, details) VALUES (%s, %s, %s, %s, %s)',
                            (admin['gym_id'], admin['id'], user_id, 'account_deactivated', Jsonb({'reason': payload.reason, 'note': payload.note})))
                cur.execute('INSERT INTO notifications (user_id, kind, title, body, payload) VALUES (%s, %s, %s, %s, %s)',
                            (user_id, 'account_deactivated', 'Tu cuenta fue dada de baja', payload.note or payload.reason,
                             Jsonb({'deactivated_at': now.isoformat(), 'reactivation_until': (now + timedelta(days=30)).isoformat()})))
    except HTTPException:
        raise
    except Exception as exc:
        db_message = f'{exc} {getattr(getattr(exc, "diag", None), "message_primary", "")}'
        if 'único administrador' in db_message:
            raise _problem(409, 'LAST_ADMIN', 'No se puede dar de baja al único administrador activo.')
        if 'Reasigna los clientes' in db_message:
            raise _problem(409, 'TRAINER_HAS_CLIENTS', 'Reasigna los clientes antes de dar de baja al entrenador.')
        raise
    notification_channel = _deliver_account_notice(
        user['email'], 'Tu cuenta fue dada de baja · MUSKL',
        f"Tu cuenta fue dada de baja por el gimnasio. Motivo: {payload.reason}. "
        f"Puedes contactar al gimnasio para solicitar más información. "
        f"La fecha límite para reactivarla es {(now + timedelta(days=30)).date().isoformat()}."
    )
    return {'id': str(user_id), 'status': 'deactivated', 'deactivated_at': now.isoformat(),
            'reactivation_until': (now + timedelta(days=30)).isoformat(),
            'notification_channel': notification_channel}


@app.patch('/api/v1/admin/members/{member_number}/deactivate')
def deactivate_member_by_number(member_number: str, payload: DeactivationRequest,
                                admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        users = conn.execute('SELECT id FROM users WHERE gym_id = %s AND upper(member_number) = upper(%s) LIMIT 2',
                             (admin['gym_id'], member_number)).fetchall()
    if not users:
        raise _problem(404, 'USER_NOT_FOUND', 'No encontramos ese número de socio.')
    if len(users) > 1:
        raise _problem(409, 'SHARED_MEMBER_NUMBER', 'Este número pertenece a un grupo. Selecciona a la persona en Usuarios.')
    return deactivate_user(users[0]['id'], payload, admin)


@app.post('/api/v1/admin/trainers/reassign')
def reassign_client(payload: ReassignTrainerRequest, admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            trainer = cur.execute("SELECT id, first_name, last_name FROM users WHERE id = %s AND gym_id = %s AND role = 'trainer' AND status = 'active' FOR UPDATE",
                                  (payload.new_trainer_id, admin['gym_id'])).fetchone()
            client = cur.execute("""SELECT u.id FROM users u JOIN client_profiles cp ON cp.user_id = u.id
                WHERE u.id = %s AND u.gym_id = %s AND u.role = 'client'
                  AND u.status IN ('active', 'active_no_onboarding')
                  AND cp.trainer_reassignment_required FOR UPDATE OF u, cp""",
                                 (payload.client_id, admin['gym_id'])).fetchone()
            if trainer is None or client is None:
                raise _problem(409, 'REASSIGNMENT_NOT_ALLOWED',
                               'El administrador solo puede reasignar cuando el entrenador anterior dejó el gimnasio.')
            cur.execute('UPDATE trainer_client_assignments SET ends_at = now() WHERE client_id = %s AND ends_at IS NULL',
                        (payload.client_id,))
            cur.execute('INSERT INTO trainer_client_assignments (trainer_id, client_id, assigned_by) VALUES (%s, %s, %s)',
                        (payload.new_trainer_id, payload.client_id, admin['id']))
            cur.execute("UPDATE client_profiles SET trainer_reassignment_required = false WHERE user_id = %s",
                        (payload.client_id,))
            cur.execute("""UPDATE client_trainer_requests SET status = 'cancelled', reviewed_at = now()
                WHERE client_id = %s AND status = 'pending'""", (payload.client_id,))
            cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                VALUES (%s, 'trainer_reassigned', 'Nuevo entrenador asignado', %s, %s)""",
                (payload.client_id,
                 f"El gimnasio te reasignó con {trainer['first_name']} {trainer['last_name']}; podrá prepararte una rutina.",
                 Jsonb({'trainer_id': str(payload.new_trainer_id)})))
    return {'client_id': str(payload.client_id), 'trainer_id': str(payload.new_trainer_id)}


@app.patch('/api/v1/admin/users/{user_id}/reactivate')
def reactivate_user(user_id: uuid.UUID, admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            user = cur.execute("SELECT id, email, status_before_deactivation FROM users WHERE id = %s AND gym_id = %s AND status = 'deactivated' AND reactivation_until >= now() FOR UPDATE",
                               (user_id, admin['gym_id'])).fetchone()
            if user is None:
                raise _problem(404, 'NOT_REACTIVATABLE', 'No hay una cuenta dada de baja dentro del plazo de reactivación.')
            cur.execute('UPDATE users SET status = COALESCE(status_before_deactivation, %s) WHERE id = %s',
                        (user['status_before_deactivation'] or 'active', user_id))
            cur.execute('INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type) VALUES (%s, %s, %s, %s)',
                        (admin['gym_id'], admin['id'], user_id, 'account_reactivated'))
            cur.execute('INSERT INTO notifications (user_id, kind, title, body) VALUES (%s, %s, %s, %s)',
                        (user_id, 'account_reactivated', 'Cuenta reactivada', 'El gimnasio reactivó tu cuenta.'))
    _deliver_notice_email(user['email'], 'Tu cuenta fue reactivada · MUSKL',
                          'El gimnasio reactivó tu cuenta. Ya puedes iniciar sesión en MUSKL.')
    return {'id': str(user_id), 'status': 'active'}


@app.patch('/api/v1/admin/members/{member_number}/reactivate')
def reactivate_member_by_number(member_number: str, admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        users = conn.execute('SELECT id FROM users WHERE gym_id = %s AND upper(member_number) = upper(%s) LIMIT 2',
                             (admin['gym_id'], member_number)).fetchall()
    if not users:
        raise _problem(404, 'USER_NOT_FOUND', 'No encontramos ese número de socio.')
    if len(users) > 1:
        raise _problem(409, 'SHARED_MEMBER_NUMBER', 'Este número pertenece a un grupo. Selecciona a la persona en Usuarios.')
    return reactivate_user(users[0]['id'], admin)
