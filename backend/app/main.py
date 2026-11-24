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
    delete_exercise_media,
    delete_profile_photo,
    presigned_certificate_url,
    presigned_exercise_media_url,
    presigned_profile_photo_url,
    put_certificate,
    put_exercise_media,
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
_firebase_app_cache = False


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
if origins:
    origins.extend(origin for origin in (
        'http://localhost:5173',
        'http://127.0.0.1:5173',
        'http://localhost:4173',
        'http://127.0.0.1:4173',
    ) if origin not in origins)
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
            await asyncio.to_thread(_deliver_client_push_reminders)
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


class PushTokenPayload(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: Literal['android', 'ios']


class PushReminderPreference(BaseModel):
    enabled: bool


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


class TrainerExerciseCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    muscle_group: Literal[
        'Pecho', 'Espalda', 'Hombros', 'Bíceps', 'Tríceps', 'Piernas',
        'Cuádriceps', 'Femoral', 'Pierna completa', 'Glúteos',
        'Pantorrillas', 'Abdomen', 'Cardio', 'Cuerpo completo',
    ]
    equipment: Literal[
        'Peso corporal', 'Mancuernas', 'Barra', 'Discos',
        'Poleas', 'Máquina', 'Bandas elásticas', 'Kettlebell', 'Otro',
    ]
    instructions: str | None = Field(default=None, max_length=2000)


class ExerciseCatalogUpdate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    muscle_group: Literal[
        'Pecho', 'Espalda', 'Hombros', 'Bíceps', 'Tríceps', 'Piernas',
        'Cuádriceps', 'Femoral', 'Pierna completa', 'Glúteos',
        'Pantorrillas', 'Abdomen', 'Cardio', 'Cuerpo completo',
    ]
    equipment: Literal[
        'Peso corporal', 'Mancuernas', 'Barra', 'Discos',
        'Poleas', 'Máquina', 'Bandas elásticas', 'Kettlebell', 'Otro',
    ]
    instructions: str | None = Field(default=None, max_length=2000)


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
    user_not_found = False
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
                    user_not_found = not candidates
                    invalid_credentials = bool(candidates)
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
    if user_not_found:
        raise _problem(401, 'USER_NOT_FOUND', 'No existe una cuenta con ese correo o identificador.')
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

            first_name        ' '.join(last_name.split()).casefold() ==
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
                        (GYM_ID, member_number)).fetchall()
                    if len(candidates) == 1:
                        registry = candidates[0]
                    elif len(candidates) > 1:
                        raise _problem(409, 'MEMBER_SELECTION_REQUIRED',
                                       'Ese número tiene varios integrantes. Busca el número y selecciona tu ficha.')

                if registry and registry['linked_user_id']:
                    raise _problem(409, 'MEMBER_ALREADY_REGISTERED',
                                   'Ese socio ya tiene una cuenta vinculada. Inicia sesión o recupera tu contraseña.')
                first_name = registry['first_name'] if registry else payload.first_name
                last_name = registry['last_name'] if registry else payload.last_name
                birth_date = registry['birth_date'] if registry else payload.birth_date
                if registry is None:
                    same_person = cur.execute("""SELECT member_number FROM client_member_registry
                        WHERE gym_id = %s
                          AND lower(trim(regexp_replace(first_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                          AND lower(trim(regexp_replace(last_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                          AND birth_date = %s LIMIT 1""",
                        (GYM_ID, _normalize_person_name(first_name, 'nombre'),
                         _normalize_person_name(last_name, 'apellido'), birth_date)).fetchone()
                    if same_person:
                        raise _problem(409, 'PERSON_NAME_IN_USE',
                                       'Ya existe una ficha con ese nombre y fecha de nacimiento. Revisa el número de socio.')
                user = _create_user(cur, role='client', status='active_no_onboarding',
                                    first_name=first_name, last_name=last_name,
                                    email=str(payload.email),
                                    phone=payload.phone or (registry['phone'] if registry else None),
                                    password=payload.password, member_number=member_number,
                                    email_verified=False, birth_date=birth_date)
                user_id = user['id']
                storage_key = _store_registration_photo(user['id'], photo)
                if storage_key:
                    cur.execute("""UPDATE users SET profile_photo_storage_key = %s,
                        profile_photo_mime = %s WHERE id = %s""",
                        (storage_key, photo[1], user['id']))
                if registry is None:
                    payment_due_on = cur.execute("SELECT (now() AT TIME ZONE timezone)::date AS date FROM gyms WHERE id = %s",
                                                 (GYM_ID,)).fetchone()['date']
                    registry = cur.execute("""INSERT INTO client_member_registry
                        (gym_id, member_number, first_name, last_name, birth_date,
                         phone, payment_due_on, linked_user_id)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id""",
                        (GYM_ID, member_number, user['first_name'], user['last_name'],
                         birth_date, user['phone'], payment_due_on, user['id'])).fetchone()
                    registry_id = registry['id']
                else:
                    payment_due_on = registry['payment_due_on']
                    cur.execute("""UPDATE client_member_registry SET linked_user_id = %s,
                        updated_at = now() WHERE id = %s AND linked_user_id IS NULL""",
                        (user['id'], registry['id']))
                    registry_id = registry['id']
                cur.execute('INSERT INTO client_profiles (user_id, birth_date, member_registry_id) VALUES (%s, %s, %s)',
                            (user['id'], birth_date, registry_id))
                group = cur.execute('''INSERT INTO client_groups (gym_id, member_number)
                    VALUES (%s, %s) ON CONFLICT (member_number) DO UPDATE
                    SET gym_id = EXCLUDED.gym_id RETURNING id''',
                            (GYM_ID, mecute('SELECT count(*) AS count FROM client_group_members WHERE group_id = %s',
                                              (group['id'],)).fetchone()['count']
                cur.execute('INSERT INTO client_group_members (group_id, user_id, is_primary) VALUES (%s, %s, %s)',
                            (group['id'], user['id'], current_members == 0))
                verification_code = _new_registration_email_code(cur, user['id'])
    except HTTPException:
        _cleanup_profile_photo(storage_key)
        raise
    except StorageNotConfigured as exc:
        _cleanup_profile_photo(storage_key)
        raise _problem(503, 'PROFILE_PHOTO_STORAGE_NOT_CONFIGURED', str(exc))
    except StorageWriteError as exc:
        _cleanup_profile_photo(storage_key)
        raise _problem(503, 'PROFILE_PHOTO_STORAGE_UNAVAILABLE', str(exc))
    except Exception:
        _cleanup_profile_photo(storage_key)
        raise
    email_sent = _deliver_registration_email_code(str(payload.email).lower(), verification_code)
    return {'status': 'verification_required', 'email_sent': email_sent,
            'message': 'Te enviamos un código para verificar tu correo.'}


@app.post('/api/v1/auth/register/trainer', status_code=202)
def register_trainer(
    first_name: Annotated[str, Form(min_length=1, max_length=80)],
    last_name: Annotated[str, Form(min_length=1, max_length=100)],
    email: Annotated[EmailStr, Form()],
    password: Annotated[str, Form(min_length=8, max_length=128)],
    specialty: Annotated[str | None, Form(max_length=120)] = None,
    phone: Annotated[str | None, Form(max_length=30)] = None,
    photo_data: Annotated[str | None, Form(max_length=2_800_000)] = None,
    photo_mime: Annotated[Literal['image/jpeg', 'image/png'] | None, Form()] = None,
    certification: UploadFile | None = File(None),
) -> dict:
    try:
        _validate_strong_password(password)
    except ValueError as exc:
        raise _problem(422, 'WEAK_PASSWORD', str(exc))
    photo = _decode_profile_photo(photo_data, photo_mime)
    ext = None
    data = None
    allowed = {'.pdf': 'application/pdf', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg'}
    if certification is not None and certification.filename:
        ext = Path(certification.filename).suffix.lower()
        if ext not in allowed or certification.content_type != allowed[ext]:
            raise _problem(415, 'INVALID_CERTIFICATION', 'Adjunta una certificación PDF, PNG o JPG.')
        data = certification.file.read(10 * 1024 * 1024 + 1)
        if not data or len(data) > 10 * 1024 * 1024:
            raise _problem(413, 'CERTIFICATION_SIZE', 'El archivo debe pesar hasta 10 MB.')
        signatures = {
            '.pdf': data.startswith(b'%PDF-'),
            '.png': data.startswith(b'\x89PNG\r\n\x1a\n'),
            '.jpg': data.startswith(b'\xff\xd8\xff'),
            '.jpeg': data.startswith(b'\xff\xd8\xff'),
        }
        if not signatures[ext]:
            raise _problem(415, 'INVALID_CERTIFICATION', 'El contenido del archivo no coincide con su formato.')
    storage_key = None
    profile_photo_key = None
    verification_code = None
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                if cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                               (GYM_ID, str(email).lower())).fetchone():
                    raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado.')
                user = _create_user(cur, role='trainer', status='pending', first_name=first_name,
                                    last_name=last_name, email=str(email), phone=phone,
                                    password=password, email_verified=False)
                verification_code = _new_registration_email_code(cur, user['id'])
                profile_photo_key = _store_registration_photo(user['id'], photo)
                if profile_photo_key:
                    cur.execute("""UPDATE users SET profile_photo_storage_key = %s,
                        profile_photo_mime = %s WHERE id = %s""",
                        (profile_photo_key, photo[1], user['id']))
                cur.execute('INSERT INTO trainer_profiles (user_id, specialty) VALUES (%s, %s)',
                            (user['id'], specialty.strip() if specialty and specialty.strip() else None))
                if certification is not None and ext and data:
                    key = f'certifications/{GYM_ID}/{user["id"]}/{uuid.uuid4()}{ext}'
                    storage_key = put_certificate(key, data, allowed[ext], UPLOAD_DIR)
                    cur.execute('INSERT INTO trainer_certifications (trainer_id, title, storage_key) VALUES (%s, %s, %s)',
                                (user['id'], Path(certification.filename or 'Certificación').name, storage_key))
                cur.execute('INSERT INTO account_audit_events (gym_id, subject_id, event_type) VALUES (%s, %s, %s)',
                            (GYM_ID, user['id'], 'trainer_registration_submitted'))
                _notify_admins_of_staff_request(cur, GYM_ID, user)
    except HTTPException:
        if storage_key:
            try:
                delete_certificate(storage_key)
                if storage_key.startswith('local://'):
                    (UPLOAD_DIR / storage_key.removeprefix('local://')).unlink(missing_ok=True)
            except Exception:
                log.exception('Could not clean up certificate object after registration failure')
        _cleanup_profile_photo(profile_photo_key)
        raise
    except StorageNotConfigured as exc:
        if storage_key:
            delete_certificate(storage_key)
        _cleanup_profile_photo(profile_photo_key)
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', str(exc))
    except StorageWriteError:
        log.exception('Certificate upload failed')
        if storage_key:
            delete_certificate(storage_key)
        _cleanup_profile_photo(profile_photo_key)
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', 'No se pudo guardar el certificado. Intenta más tarde.')
    except Exception:
        if storage_key:
            try:
                delete_certificate(storage_key)
                if storage_key.startswith('local://'):
                    (UPLOAD_DIR / storage_key.removeprefix('local://')).unlink(missing_ok=True)
            except Exception:
                log.exception('Could not clean up certificate object after registration failure')
        _cleanup_profile_photo(profile_photo_key)
        raise
    email_sent = _deliver_registration_email_code(str(email).lower(), verification_code)
    return {'status': 'verification_required', 'email_sent': email_sent,
            'message': 'Te enviamos un código para verificar tu correo. Después, tu solicitud quedará en revisión.'}


@app.post('/api/v1/auth/register/admin', status_code=202)
def register_admin(payload: AdminRegistration) -> dict:
    photo = _decode_profile_photo(payload.photo_data, payload.photo_mime)
    profile_photo_key = None
    verification_code = None
    token_hash = hashlib.sha256(payload.invite_token.strip().encode()).hexdigest()
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                invite = cur.execute(
                """SELECT id FROM admin_invite_tokens
                   WHERE gym_id = %s AND token_hash = %s AND revoked_at IS NULL AND used_at IS NULL
                     AND (expires_at IS NULL OR expires_at > now()) FOR UPDATE""",
                (GYM_ID, token_hash)).fetchone()
                if invite is None:
                    raise _problem(400, 'INVALID_INVITE', 'El token no es válido o ya fue usado.')
                if cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                               (GYM_ID, str(payload.email).lower())).fetchone():
                    raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado.')
                user = _create_user(cur, role='admin', status='pending', first_name=payload.first_name,
                                    last_name=payload.last_name, email=str(payload.email), phone=payload.phone,
                                    password=payload.password, email_verified=False)
                verification_code = _new_registration_email_code(cur, user['id'])
                profile_photo_key = _store_registration_photo(user['id'], photo)
                if profile_photo_key:
                    cur.execute("""UPDATE users SET profile_photo_storage_key = %s,
                        profile_photo_mime = %s WHERE id = %s""",
                        (profile_photo_key, photo[1], user['id']))
                cur.execute('UPDATE admin_invite_tokens SET used_at = now() WHERE id = %s', (invite['id'],))
                cur.execute('INSERT INTO account_audit_events (gym_id, subject_id, event_type) VALUES (%s, %s, %s)',
                            (GYM_ID, user['id'], 'admin_registration_submitted'))
                _notify_admins_of_staff_request(cur, GYM_ID, user)
    except HTTPException:
        _cleanup_profile_photo(profile_photo_key)
        raise
    except StorageNotConfigured as exc:
        _cleanup_profile_photo(profile_photo_key)
        raise _problem(503, 'PROFILE_PHOTO_STORAGE_NOT_CONFIGURED', str(exc))
    except StorageWriteError as exc:
        _cleanup_profile_photo(profile_photo_key)
        raise _problem(503, 'PROFILE_PHOTO_STORAGE_UNAVAILABLE', str(exc))
    except Exception:
        _cleanup_profile_photo(profile_photo_key)
        raise
    email_sent = _deliver_registration_email_code(str(payload.email).lower(), verification_code)
    return {'status': 'verification_required', 'email_sent': email_sent,
            'message': 'Te enviamos un código para verificar tu correo. Después, tu solicitud quedará en revisión.'}


def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    if credentials is None:
        raise _problem(401, 'AUTH_REQUIRED', 'Inicia sesión para continuar.')
    try:
        claims = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id, sid = uuid.UUID(claims['sub']), uuid.UUID(claims['sid'])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise _problem(401, 'INVALID_SESSION', 'La sesión venció. Inicia sesión de nuevo.')
    with pool.connection() as conn:
        user = conn.execute(
            """SELECT u.*, concat_ws(' ', a.first_name, a.last_name) AS deactivated_by_name
               FROM users u JOIN auth_sessions s ON s.user_id = u.id
               LEFT JOIN users a ON a.id = u.deactivated_by
               WHERE u.id = %s AND s.id = %s AND s.revoked_at IS NULL
                 AND s.expires_at > now() AND s.session_version = u.session_version
                 AND u.session_version = %s""",
            (user_id, sid, claims.get('ver'))).fetchone()
    if user is None:
        raise _problem(401, 'INVALID_SESSION', 'La sesión venció. Inicia sesión de nuevo.')
    user['session_id'] = sid
    return user


def active_admin(user: dict = Depends(current_user)) -> dict:
    if user['role'] != 'admin' or user['status'] != 'active':
        raise _problem(403, 'ADMIN_REQUIRED', 'Esta acción requiere una cuenta admin activa.')
    return user


def active_client(user: dict = Depends(current_user)) -> dict:
    if user['role'] != 'client' or user['status'] not in ('active_no_onboarding', 'active'):
        raise _problem(403, 'CLIENT_REQUIRED', 'Esta opción requiere una cuenta cliente activa.')
    return _repair_completed_client_onboarding(user)


def _repair_completed_client_onboarding(user: dict) -> dict:
    """Correct legacy clients whose saved onboarding was not reflected in status."""
    if user['role'] != 'client' or user['status'] != 'active_no_onboarding':
        return user
    with pool.connection() as conn:
        with conn.cursor() as cur:
            completed = cur.execute("""SELECT cp.onboarding_completed_at,
                    cp.goal, cp.days_per_week, cp.weight_kg,
                    EXISTS (SELECT 1 FROM memberships m WHERE m.client_id = u.id
                        AND m.status = 'active') AS has_membership
                FROM users u LEFT JOIN client_profiles cp ON cp.user_id = u.id
                WHERE u.id = %s""", (user['id'],)).fetchone()
            profile_is_complete = (completed is not None
                and completed['goal'] is not None
                and completed['days_per_week'] is not None
                and completed['weight_kg'] is not None
                and completed['has_membership'])
            if completed and (completed['onboarding_completed_at'] or profile_is_complete):
                cur.execute("""UPDATE client_profiles SET
                    onboarding_completed_at = COALESCE(onboarding_completed_at, now()),
                    updated_at = now() WHERE user_id = %s""", (user['id'],))
                return cur.execute("""UPDATE users SET status = 'active', updated_at = now()
                    WHERE id = %s RETURNING *""", (user['id'],)).fetchone()
    return user


@app.post('/api/v1/client/group-members', status_code=201)
def register_client_group_members(payload: ClientGroupRegistration,
                                  background_tasks: BackgroundTasks,
                                  client: dict = Depends(active_client)) -> dict:
    pending_codes: list[tuple[str, str]] = []
    emails = [str(member.email).lower() for member in payload.members]
    if len(set(emails)) != len(emails):
        raise _problem(422, 'DUPLICATE_GROUP_EMAIL', 'Cada integrante debe usar un correo diferente.')
    with pool.connection() as conn:
        with conn.cursor() as cur:
            group = cur.execute("""SELECT g.id, g.member_number, g.plan_id, m.is_primary,
                    (SELECT count(*) FROM client_group_members gm WHERE gm.group_id = g.id) AS current_size
                FROM client_groups g JOIN client_group_members m ON m.group_id = g.id
                WHERE m.user_id = %s AND g.gym_id = %s FOR UPDATE OF g""",
                (client['id'], client['gym_id'])).fetchone()
            if group is None or not group['is_primary']:
                raise _problem(403, 'GROUP_OWNER_REQUIRED', 'Solo quien inició el grupo puede agregar integrantes.')
            plan = cur.execute("""SELECT id, name, min_group_size, max_group_size
                FROM membership_plans WHERE id = %s AND gym_id = %s AND active""",
                (payload.plan_id, client['gym_id'])).fetchone()
            if plan is None or plan['min_group_size'] < 2:
                raise _problem(422, 'NOT_A_GROUP_PLAN', 'El plan seleccionado no admite registro grupal.')
            target_size = len(payload.members) + 1
            if not plan['min_group_size'] <= target_size <= plan['max_group_size']:
                raise _problem(422, 'GROUP_SIZE_INVALID',
                    f"El plan {plan['name']} requiere de {plan['min_group_size']} a {plan['max_group_size']} integrantes.")
            if group['current_size'] > 1:
                if group['plan_id'] == payload.plan_id and group['current_size'] == target_size:
                    return {'member_number': group['member_number'], 'member_count': target_size, 'created': False}
                raise _problem(409, 'GROUP_ALREADY_REGISTERED', 'Este grupo ya tiene integrantes registrados.')
            if cur.execute("SELECT 1 FROM memberships WHERE client_id = %s AND status = 'active'",
                           (client['id'],)).fetchone():
                raise _problem(409, 'GROUP_REGISTRATION_CLOSED', 'La membresía ya fue activada para esta cuenta.')
            for member in payload.members:
                email = str(member.email).lower()
                if cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                               (client['gym_id'], email)).fetchone():
                    raise _problem(409, 'EMAIL_IN_USE', f'El correo {email} ya está registrado.')
                registry = cur.execute("""SELECT id, first_name, last_name, birth_date,
                        phone, linked_user_id FROM client_member_registry
                    WHERE gym_id = %s
                      AND upper(trim(regexp_replace(member_number, '[[:space:]]+', ' ', 'g'))) = %s
                      AND lower(trim(regexp_replace(first_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                      AND lower(trim(regexp_replace(last_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                      AND birth_date = %s FOR UPDATE""",
                    (client['gym_id'], group['member_number'], member.first_name,
                     member.last_name, member.birth_date)).fetchone()
                if registry and registry['linked_user_id']:
                    raise _problem(409, 'MEMBER_ALREADY_REGISTERED',
                                   f'{member.first_name} {member.last_name} ya tiene una cuenta vinculada.')
                first_name = registry['first_name'] if registry else member.first_name
                last_name = registry['last_name'] if registry else member.last_name
                birth_date = registry['birth_date'] if registry else member.birth_date
                if registry is None:
                    same_person = cur.execute("""SELECT member_number FROM client_member_registry
                        WHERE gym_id = %s
                          AND lower(trim(regexp_replace(first_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                          AND lower(trim(regexp_replace(last_name, '[[:space:]]+', ' ', 'g'))) = lower(%s)
                          AND birth_date = %s LIMIT 1""",
                        (client['gym_id'], _normalize_person_name(first_name, 'nombre'),
                         _normalize_person_name(last_name, 'apellido'), birth_date)).fetchone()
                    if same_person:
                        raise _problem(409, 'PERSON_NAME_IN_USE',
                                       'Ya existe una ficha con ese nombre y fecha de nacimiento.')
                user = _create_user(cur, role='client', status='active_no_onboarding',
                    first_name=first_name, last_name=last_name, email=email,
                    phone=member.phone or (registry['phone'] if registry else None),
                    password=member.password,
                    member_number=group['member_number'], email_verified=False,
                    birth_date=birth_date)
                pending_codes.append((email, _new_registration_email_code(cur, user['id'])))
                if registry is None:
                    payment_due_on = cur.execute("SELECT (now() AT TIME ZONE timezone)::date AS date FROM gyms WHERE id = %s",
                                                 (client['gym_id'],)).fetchone()['date']
                    registry = cur.execute("""INSERT INTO client_member_registry
                        (gym_id, member_number, first_name, last_name, birth_date,
                         phone, payment_due_on, linked_user_id)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id""",
                        (client['gym_id'], group['member_number'], user['first_name'],
                         user['last_name'], birth_date, user['phone'], payment_due_on,
                         user['id'])).fetchone()
                    registry_id = registry['id']
                else:
                    registry_id = registry['id']
                    cur.execute("""UPDATE client_member_registry SET linked_user_id = %s,
                        updated_at = now() WHERE id = %s AND linked_user_id IS NULL""",
                        (user['id'], registry_id))
                cur.execute('INSERT INTO client_profiles (user_id, birth_date, member_registry_id) VALUES (%s, %s, %s)',
                            (user['id'], birth_date, registry_id))
                cur.execute('INSERT INTO client_group_members (group_id, user_id) VALUES (%s, %s)',
                            (group['id'], user['id']))
            cur.execute('UPDATE client_groups SET plan_id = %s WHERE id = %s',
                        (payload.plan_id, group['id']))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'client_group_registered', %s)",
                        (client['gym_id'], client['id'], Jsonb({'plan_id': str(plan['id']), 'member_count': target_size})))
    for email, code in pending_codes:
        background_tasks.add_task(_deliver_registration_email_code, email, code)
    return {'member_number': group['member_number'], 'member_count': target_size, 'created': True}


def active_trainer(user: dict = Depends(current_user)) -> dict:
    if user['role'] != 'trainer' or user['status'] != 'active':
        raise _problem(403, 'TRAINER_REQUIRED', 'Esta opción requiere una cuenta entrenador activa.')
    return user


@app.get('/api/v1/auth/me')
def me(user: dict = Depends(current_user)) -> dict:
    # A session restore is the first request after login/app launch. Repair
    # legacy completed client profiles here so the router opens the client home.
    user = _repair_completed_client_onboarding(user)
    return {'user': _public_user(user)}


def _signed_profile_photo(storage_key: str | None) -> str | None:
    if not storage_key:
        return None
    try:
        return presigned_profile_photo_url(storage_key, expires_in=600)
    except (StorageNotConfigured, StorageReadError):
        log.exception('Could not create temporary profile photo URL')
        return None


@app.get('/api/v1/profile')
def own_profile(user: dict = Depends(current_user)) -> dict:
    return {
        'first_name': user['first_name'],
        'last_name': user['last_name'],
        'email': user['email'],
        'phone': user['phone'],
        'bio': user.get('bio'),
        'role': user['role'],
        'profile_photo_url': _signed_profile_photo(user.get('profile_photo_storage_key')),
        'profile_photo_mime': user.get('profile_photo_mime'),
    }


@app.patch('/api/v1/profile')
def update_own_profile(payload: OwnProfileUpdate,
                       user: dict = Depends(current_user)) -> dict:
    if user['role'] != 'admin':
        raise _problem(403, 'PROFILE_ROUTE_ROLE', 'Usa el apartado de perfil de tu cuenta.')
    first_name = _normalize_person_name(payload.first_name, 'nombre')
    last_name = _normalize_person_name(payload.last_name, 'apellido')
    phone = payload.phone.strip() if payload.phone and payload.phone.strip() else None
    bio = payload.bio.strip() if payload.bio and payload.bio.strip() else None
    changed = (first_name != user['first_name'] or last_name != user['last_name']
               or phone != user.get('phone') or bio != user.get('bio'))
    identity_changed = (first_name != user['first_name']
                        or last_name != user['last_name']
                        or phone != user.get('phone'))
    with pool.connection() as conn:
        with conn.cursor() as cur:
            if identity_changed:
                _ensure_profile_edit_window(cur, user['id'])
            _ensure_unique_person_name(cur, user['gym_id'], first_name, last_name, user['id'])
            cur.execute("""UPDATE users SET first_name = %s, last_name = %s,
                phone = %s, bio = %s,
                profile_details_updated_at = CASE WHEN %s THEN now() ELSE profile_details_updated_at END,
                updated_at = now() WHERE id = %s""",
                (first_name, last_name, phone, bio, identity_changed, user['id']))
            if changed:
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, subject_id, event_type)
                    VALUES (%s, %s, %s, 'admin_profile_updated')""",
                    (user['gym_id'], user['id'], user['id']))
                cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                    VALUES (%s, 'profile_updated', 'Perfil actualizado',
                        'Se guardaron cambios en tus datos personales.', %s)""",
                    (user['id'], Jsonb({'event': 'admin_profile_updated'})))
    return own_profile({**user, 'first_name': first_name, 'last_name': last_name,
                        'phone': phone, 'bio': bio})


@app.patch('/api/v1/profile/photo')
def update_own_profile_photo(payload: ProfilePhotoUpdate,
                             user: dict = Depends(current_user)) -> dict:
    if user['status'] not in ('active', 'active_no_onboarding'):
        raise _problem(403, 'ACTIVE_ACCOUNT_REQUIRED', 'La cuenta debe estar activa.')
    if payload.photo_data is None and payload.photo_mime is None and not payload.remove_photo:
        raise _problem(422, 'EMPTY_PROFILE_UPDATE', 'Incluye una foto o indica que quieres quitarla.')
    if payload.photo_data is not None and payload.remove_photo:
        raise _problem(422, 'INVALID_PROFILE_PHOTO', 'Elige una foto nueva o quita la foto actual.')

    photo_bytes = None
    if payload.photo_data is not None:
        if payload.photo_mime is None:
            raise _problem(415, 'INVALID_PROFILE_PHOTO', 'El formato de la foto no es válido.')
        try:
            photo_bytes = base64.b64decode(payload.photo_data, validate=True)
        except (ValueError, binascii.Error):
            raise _problem(415, 'INVALID_PROFILE_PHOTO', 'No se pudo leer la imagen seleccionada.')
        if not photo_bytes or len(photo_bytes) > 2 * 1024 * 1024:
            raise _problem(413, 'PROFILE_PHOTO_SIZE', 'La foto debe pesar máximo 2 MB.')
        valid_signature = (
            payload.photo_mime == 'image/jpeg' and photo_bytes.startswith(b'\xff\xd8\xff')
        ) or (
            payload.photo_mime == 'image/png' and photo_bytes.startswith(b'\x89PNG\r\n\x1a\n')
        )
        if not valid_signature:
            raise _problem(415, 'INVALID_PROFILE_PHOTO', 'Usa una imagen JPG o PNG válida.')
    elif payload.photo_mime is not None:
        raise _problem(415, 'INVALID_PROFILE_PHOTO', 'Faltan los datos de la foto seleccionada.')

    new_storage_key = None
    if photo_bytes is not None:
        extension = 'jpg' if payload.photo_mime == 'image/jpeg' else 'png'
        try:
            new_storage_key = put_profile_photo(
                f"profile-photos/{user['id']}/{uuid.uuid4()}.{extension}",
                photo_bytes, payload.photo_mime)
        except StorageNotConfigured as exc:
            raise _problem(503, 'PROFILE_PHOTO_STORAGE_NOT_CONFIGURED', str(exc))
        except StorageWriteError as exc:
            raise _problem(503, 'PROFILE_PHOTO_STORAGE_UNAVAILABLE', str(exc))

    old_storage_key = user.get('profile_photo_storage_key')
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                if payload.remove_photo:
                    cur.execute("""UPDATE users SET profile_photo_storage_key = NULL,
                        profile_photo_mime = NULL, updated_at = now() WHERE id = %s""",
                        (user['id'],))
                elif new_storage_key:
                    cur.execute("""UPDATE users SET profile_photo_storage_key = %s,
                        profile_photo_mime = %s, updated_at = now() WHERE id = %s""",
                        (new_storage_key, payload.photo_mime, user['id']))
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, subject_id, event_type, details)
                    VALUES (%s, %s, %s, 'profile_photo_updated', %s)""",
                    (user['gym_id'], user['id'], user['id'],
                     Jsonb({'removed': payload.remove_photo})))
    except Exception:
        if new_storage_key:
            try:
                delete_profile_photo(new_storage_key)
            except Exception:
                log.exception('Could not clean up profile photo after database update failed')
        raise
    if old_storage_key and (payload.remove_photo or new_storage_key):
        try:
            delete_profile_photo(old_storage_key)
        except Exception:
            log.exception('Could not remove replaced profile photo from R2')
    return own_profile({**user,
                        'profile_photo_storage_key': None if payload.remove_photo else new_storage_key,
                        'profile_photo_mime': None if payload.remove_photo else payload.photo_mime})


@app.post('/api/v1/auth/refresh')
def refresh_session(payload: RefreshRequest) -> dict:
    now = datetime.now(UTC)
    next_access_expires = now + timedelta(minutes=ACCESS_TOKEN_MINUTES)
    next_refresh_token = secrets.token_urlsafe(48)
    next_refresh_expires = now + timedelta(days=REFRESH_TOKEN_DAYS)
    with pool.connection() as conn:
        with conn.cursor() as cur:
            session = cur.execute("""SELECT s.id AS session_id, u.*,
                    concat_ws(' ', a.first_name, a.last_name) AS deactivated_by_name
                FROM auth_sessions s JOIN users u ON u.id = s.user_id
                LEFT JOIN users a ON a.id = u.deactivated_by
                WHERE s.refresh_token_hash = %s AND s.revoked_at IS NULL
                  AND s.refresh_expires_at > now()
                  AND s.session_version = u.session_version
                FOR UPDATE OF s""", (_refresh_hash(payload.refresh_token),)).fetchone()
            if session is None:
                raise _problem(401, 'INVALID_REFRESH_TOKEN', 'La sesión venció. Inicia sesión de nuevo.')
            cur.execute("""UPDATE auth_sessions SET expires_at = %s,
                refresh_token_hash = %s, refresh_expires_at = %s WHERE id = %s""",
                (next_access_expires, _refresh_hash(next_refresh_token),
                 next_refresh_expires, session['session_id']))
            response = {
                'access_token': _token_for(session, session['session_id'], next_access_expires),
                'refresh_token': next_refresh_token,
                'token_type': 'Bearer',
                'expires_at': next_access_expires.isoformat(),
                'user': _public_user(session),
            }
    return response


@app.post('/api/v1/auth/session-status')
def deactivated_session_status(payload: RefreshRequest) -> dict:
    """Return only a deactivation notice for a revoked session's owner."""
    with pool.connection() as conn:
        user = conn.execute("""SELECT u.*, concat_ws(' ', a.first_name, a.last_name)
                AS deactivated_by_name
            FROM auth_sessions s JOIN users u ON u.id = s.user_id
            LEFT JOIN users a ON a.id = u.deactivated_by
            WHERE s.refresh_token_hash = %s AND s.revoked_at IS NOT NULL
              AND s.refresh_expires_at > now() AND u.status = 'deactivated'
            LIMIT 1""", (_refresh_hash(payload.refresh_token),)).fetchone()
    if user is None:
        raise _problem(401, 'INVALID_SESSION_STATUS', 'La sesión venció. Inicia sesión de nuevo.')
    return {'user': {
        'role': user['role'],
        'status': user['status'],
        'member_number': user['member_number'],
        'status_reason': user['status_reason'],
        'deactivation_reason': user['deactivation_reason'],
        'deactivated_at': user['deactivated_at'].isoformat() if user['deactivated_at'] else None,
        'deactivated_by': user['deactivated_by_name'],
        'reactivation_until': user['reactivation_until'].isoformat() if user['reactivation_until'] else None,
    }}


@app.get('/api/v1/trainer/profile')
def trainer_profile(trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        profile = conn.execute("""SELECT u.first_name, u.last_name, u.email, u.phone,
                u.profile_photo_storage_key, u.profile_photo_mime,
                tp.specialty, tp.bio, tp.notification_preferences,
                coalesce((SELECT jsonb_agg(jsonb_build_object('id', tc.id, 'title', tc.title,
                    'verified_at', tc.verified_at) ORDER BY tc.created_at)
                    FROM trainer_certifications tc WHERE tc.trainer_id = u.id), '[]'::jsonb) AS certifications
            FROM users u JOIN trainer_profiles tp ON tp.user_id = u.id WHERE u.id = %s""",
            (trainer['id'],)).fetchone()
    result = dict(profile)
    result['profile_photo_url'] = _signed_profile_photo(result.pop('profile_photo_storage_key'))
    return result


@app.get('/api/v1/trainer/certifications/{certification_id}/download')
def trainer_certification_download(
    certification_id: uuid.UUID,
    trainer: dict = Depends(active_trainer),
) -> dict:
    with pool.connection() as conn:
        certificate = conn.execute(
            'SELECT storage_key FROM trainer_certifications WHERE id = %s AND trainer_id = %s',
            (certification_id, trainer['id'])).fetchone()
    if certificate is None:
        raise _problem(404, 'CERTIFICATION_NOT_FOUND', 'No encontramos ese certificado.')
    if not certificate['storage_key'].startswith('r2://'):
        raise _problem(410, 'CERTIFICATION_NEEDS_MIGRATION',
                       'Este certificado aún no está en el almacenamiento privado.')
    try:
        url = presigned_certificate_url(certificate['storage_key'], expires_in=600)
    except StorageNotConfigured:
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', 'El almacenamiento privado no está disponible.')
    except StorageReadError:
        log.exception('Could not create trainer certificate link')
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', 'No se pudo generar el enlace temporal.')
    return {'url': url, 'expires_in': 600}


@app.put('/api/v1/trainer/certifications/{certification_id}')
def replace_trainer_certification(
    certification_id: uuid.UUID,
    certification: UploadFile = File(...),
    trainer: dict = Depends(active_trainer),
) -> dict:
    ext = Path(certification.filename or '').suffix.lower()
    allowed = {
        '.pdf': ('application/pdf', b'%PDF-'),
        '.png': ('image/png', b'\x89PNG\r\n\x1a\n'),
        '.jpg': ('image/jpeg', b'\xff\xd8\xff'),
        '.jpeg': ('image/jpeg', b'\xff\xd8\xff'),
    }
    file_type = allowed.get(ext)
    if file_type is None or certification.content_type != file_type[0]:
        raise _problem(415, 'INVALID_CERTIFICATION', 'Adjunta una certificación PDF, PNG o JPG.')
    data = certification.file.read(10 * 1024 * 1024 + 1)
    if not data or len(data) > 10 * 1024 * 1024:
        raise _problem(413, 'CERTIFICATION_SIZE', 'El archivo debe pesar hasta 10 MB.')
    if not data.startswith(file_type[1]):
        raise _problem(415, 'INVALID_CERTIFICATION', 'El contenido del archivo no coincide con su formato.')

    new_storage_key = None
    old_storage_key = None
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                certificate = cur.execute(
                    'SELECT storage_key FROM trainer_certifications WHERE id = %s AND trainer_id = %s FOR UPDATE',
                    (certification_id, trainer['id'])).fetchone()
                if certificate is None:
                    raise _problem(404, 'CERTIFICATION_NOT_FOUND', 'No encontramos ese certificado.')
                old_storage_key = certificate['storage_key']
                object_key = f"certifications/{GYM_ID}/{trainer['id']}/{uuid.uuid4()}{ext}"
                new_storage_key = put_certificate(object_key, data, file_type[0], UPLOAD_DIR)
                cur.execute("""UPDATE trainer_certifications
                    SET title = %s, storage_key = %s, verified_at = NULL, verified_by = NULL
                    WHERE id = %s AND trainer_id = %s""",
                    (Path(certification.filename or 'Certificación').name,
                     new_storage_key, certification_id, trainer['id']))
    except HTTPException:
        if new_storage_key:
            try:
                delete_certificate(new_storage_key)
                if new_storage_key.startswith('local://'):
                    (UPLOAD_DIR / new_storage_key.removeprefix('local://')).unlink(missing_ok=True)
            except Exception:
                log.exception('Could not clean up replacement certificate after failure')
        raise
    except StorageNotConfigured as exc:
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', str(exc))
    except StorageWriteError:
        log.exception('Replacement certificate upload failed')
        raise _problem(503, 'CERT_STORAGE_UNAVAILABLE', 'No se pudo guardar el certificado. Intenta más tarde.')
    except Exception:
        if new_storage_key:
            try:
                delete_certificate(new_storage_key)
                if new_storage_key.startswith('local://'):
                    (UPLOAD_DIR / new_storage_key.removeprefix('local://')).unlink(missing_ok=True)
            except Exception:
                log.exception('Could not clean up replacement certificate after failure')
        raise

    if old_storage_key and old_storage_key.startswith('r2://'):
        try:
            delete_certificate(old_storage_key)
        except Exception:
            log.exception('Could not remove replaced certificate object')
    return {'message': 'Certificado actualizado. Está pendiente de verificación.'}


@app.patch('/api/v1/trainer/profile')
def update_trainer_profile(payload: TrainerProfileUpdate,
                           trainer: dict = Depends(active_trainer)) -> dict:
    if str(payload.email).lower() != trainer['email']:
        raise _problem(409, 'EMAIL_CHANGE_VERIFICATION_REQUIRED',
                       'Verifica el nuevo correo antes de guardar el cambio.')
    allowed_preferences = {'client_activity', 'routine_expiry', 'daily_reminder'}
    preferences = {key: payload.notification_preferences.get(key, False)
                   for key in allowed_preferences}
    first_name = _normalize_person_name(payload.first_name, 'nombre')
    last_name = _normalize_person_name(payload.last_name, 'apellido')
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                before = cur.execute("""SELECT u.first_name, u.last_name, u.phone,
                        tp.specialty, tp.bio
                    FROM users u JOIN trainer_profiles tp ON tp.user_id = u.id
                    WHERE u.id = %s FOR UPDATE OF u""", (trainer['id'],)).fetchone()
                identity_changed = bool(before and (
                    before['first_name'] != first_name or before['last_name'] != last_name
                    or before['phone'] != (payload.phone.strip() if payload.phone else None)))
                details_changed = bool(identity_changed or (before and (
                    before['specialty'] != (payload.specialty.strip() if payload.specialty else None)
                    or before['bio'] != (payload.bio.strip() if payload.bio else None))))
                if identity_changed:
                    _ensure_profile_edit_window(cur, trainer['id'])
                _ensure_unique_person_name(cur, trainer['gym_id'], first_name,
                                           last_name, trainer['id'])
                cur.execute("""UPDATE users SET first_name = %s, last_name = %s,
                    email = %s, phone = %s,
                    profile_details_updated_at = CASE WHEN %s THEN now() ELSE profile_details_updated_at END,
                    updated_at = now() WHERE id = %s""",
                    (first_name, last_name,
                     str(payload.email).lower(), payload.phone.strip() if payload.phone else None,
                     identity_changed, trainer['id']))
                cur.execute("""UPDATE trainer_profiles SET specialty = %s, bio = %s,
                    notification_preferences = %s, updated_at = now() WHERE user_id = %s""",
                    (payload.specialty.strip() if payload.specialty else None,
                     payload.bio.strip() if payload.bio else None, Jsonb(preferences), trainer['id']))
                cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'trainer_profile_updated', %s)",
                    (trainer['gym_id'], trainer['id'], Jsonb({'email': str(payload.email)})))
                if details_changed:
                    cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                        VALUES (%s, 'profile_updated', 'Perfil actualizado',
                            'Se guardaron cambios en tus datos personales o profesionales.', %s)""",
                        (trainer['id'], Jsonb({'event': 'trainer_profile_updated'})))
    except Exception as exc:
        constraint = getattr(getattr(exc, 'diag', None), 'constraint_name', '')
        if constraint == 'users_email_per_gym_uq':
            raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado en el gimnasio.')
        raise
    return trainer_profile(trainer)


@app.post('/api/v1/auth/email-change/code', status_code=202)
def send_email_change_code(payload: EmailChangeRequest,
                           user: dict = Depends(current_user)) -> dict:
    new_email = str(payload.new_email).lower()
    if new_email == user['email']:
        raise _problem(409, 'EMAIL_UNCHANGED', 'Ese correo ya está asociado a tu cuenta.')
    code = f'{secrets.randbelow(1_000_000):06d}'
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute('SELECT id FROM users WHERE id = %s FOR UPDATE', (user['id'],))
            cur.execute("DELETE FROM email_change_codes WHERE created_at < now() - interval '2 days'")
            if cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                           (user['gym_id'], new_email)).fetchone():
                raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado en el gimnasio.')
            recent = cur.execute("""SELECT count(*) AS n FROM email_change_codes
                WHERE user_id = %s AND created_at > now() - interval '1 hour'""",
                (user['id'],)).fetchone()['n']
            if recent >= 3:
                raise _problem(429, 'CODE_RATE_LIMIT',
                               'Ya solicitaste varios códigos. Intenta de nuevo más tarde.')
            cur.execute("""UPDATE email_change_codes SET consumed_at = now()
                WHERE user_id = %s AND consumed_at IS NULL""", (user['id'],))
            cur.execute("""INSERT INTO email_change_codes
                (user_id, new_email, code_hash, expires_at)
                VALUES (%s, %s, %s, now() + interval '10 minutes')""",
                (user['id'], new_email, _email_hash_code(code)))
    try:
        channel = _deliver_auth_code(new_email, code, 'email_change')
    except Exception:
        with pool.connection() as conn:
            conn.execute("""UPDATE email_change_codes SET consumed_at = now()
                WHERE user_id = %s AND consumed_at IS NULL""", (user['id'],))
        log.exception('Could not deliver email change code for user %s', user['id'])
        raise _problem(503, 'CODE_DELIVERY_UNAVAILABLE',
                       'No se pudo enviar el código. Intenta de nuevo más tarde.')
    return {'message': 'Enviamos un código al nuevo correo.', 'channel': channel}


@app.post('/api/v1/auth/email-change/confirm')
def confirm_email_change(payload: EmailChangeConfirmRequest,
                         user: dict = Depends(current_user)) -> dict:
    try:
        password_hasher.verify(user['password_hash'], payload.current_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        raise _problem(400, 'CURRENT_PASSWORD_INVALID', 'La contraseña actual no es correcta.')

    invalid_code = False
    email_in_use = False
    changed_email = None
    with pool.connection() as conn:
        with conn.cursor() as cur:
            pending = cur.execute("""SELECT id, new_email, code_hash, attempts
                FROM email_change_codes WHERE user_id = %s AND consumed_at IS NULL
                  AND expires_at > now() AND attempts < 5
                ORDER BY created_at DESC LIMIT 1 FOR UPDATE""", (user['id'],)).fetchone()
            if pending is None or not secrets.compare_digest(
                    pending['code_hash'], _email_hash_code(payload.code)):
                if pending is not None:
                    cur.execute('UPDATE email_change_codes SET attempts = attempts + 1 WHERE id = %s',
                                (pending['id'],))
                invalid_code = True
            elif cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s AND id <> %s',
                             (user['gym_id'], pending['new_email'], user['id'])).fetchone():
                cur.execute('UPDATE email_change_codes SET consumed_at = now() WHERE id = %s',
                            (pending['id'],))
                email_in_use = True
            else:
                changed_email = pending['new_email']
                cur.execute('UPDATE users SET email = %s, updated_at = now() WHERE id = %s',
                            (changed_email, user['id']))
                cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                    VALUES (%s, 'profile_updated', 'Correo actualizado',
                        'Tu correo electrónico se verificó y actualizó correctamente.', %s)""",
                    (user['id'], Jsonb({'event': 'email_updated'})))
                cur.execute('UPDATE email_change_codes SET consumed_at = now() WHERE id = %s',
                            (pending['id'],))
                cur.execute("""UPDATE auth_sessions SET revoked_at = now()
                    WHERE user_id = %s AND id <> %s AND revoked_at IS NULL""",
                    (user['id'], user['session_id']))
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, subject_id, event_type, details)
                    VALUES (%s, %s, %s, 'email_changed', %s)""",
                    (user['gym_id'], user['id'], user['id'], Jsonb({'email_changed': True})))
    if invalid_code:
        raise _problem(400, 'INVALID_CODE', 'El código es incorrecto o ya venció.')
    if email_in_use:
        raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado en el gimnasio.')
    _deliver_notice_email(user['email'], 'Cambio de correo en MUSKL',
                          f'El correo de tu cuenta cambió a {changed_email}. Si no hiciste este cambio, contacta al gimnasio.')
    _deliver_notice_email(changed_email, 'Correo actualizado en MUSKL',
                          'Este correo quedó vinculado a tu cuenta MUSKL.')
    return {'status': 'updated', 'email': changed_email}


@app.patch('/api/v1/auth/password')
def change_password(payload: PasswordChangeRequest,
                    user: dict = Depends(current_user)) -> dict:
    try:
        password_hasher.verify(user['password_hash'], payload.current_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        raise _problem(400, 'CURRENT_PASSWORD_INVALID', 'La contraseña actual no es correcta.')
    code_valid = False
    with pool.connection() as conn:
        with conn.cursor() as cur:
            code_valid = _valid_reset_code(
                cur, user['email'], payload.code, purpose='change', consume=True)
            if code_valid:
                cur.execute('UPDATE users SET password_hash = %s, updated_at = now() WHERE id = %s',
                    (password_hasher.hash(payload.new_password), user['id']))
                cur.execute('UPDATE auth_sessions SET revoked_at = now() WHERE user_id = %s AND id <> %s AND revoked_at IS NULL',
                    (user['id'], user['session_id']))
                cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type) VALUES (%s, %s, 'password_changed')",
                    (user['gym_id'], user['id']))
    if not code_valid:
        raise _problem(400, 'INVALID_CODE', 'El código es incorrecto o ya venció.')
    _deliver_account_notice(
        user.get('email'), 'Tu contraseña cambió · MUSKL',
        'La contraseña de tu cuenta MUSKL fue actualizada. Si no hiciste este cambio, contacta al gimnasio de inmediato.')
    return {'status': 'updated'}


@app.post('/api/v1/auth/password/change-code', status_code=202)
def send_password_change_code(payload: PasswordChangeCodeRequest,
                             user: dict = Depends(current_user)) -> dict:
    try:
        password_hasher.verify(user['password_hash'], payload.current_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        raise _problem(400, 'CURRENT_PASSWORD_INVALID', 'La contraseña actual no es correcta.')
    code = f'{secrets.randbelow(1_000_000):06d}'
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                recent = cur.execute(
                    """SELECT count(*) AS n FROM password_reset_codes
                       WHERE user_id = %s AND purpose = 'change'
                         AND created_at > now() - interval '1 hour'""",
                    (user['id'],)).fetchone()['n']
                if recent >= 3:
                    raise _problem(429, 'CODE_RATE_LIMIT',
                                   'Ya solicitaste varios códigos. Intenta de nuevo más tarde.')
                cur.execute("""UPDATE password_reset_codes SET consumed_at = now()
                    WHERE user_id = %s AND purpose = 'change' AND consumed_at IS NULL""",
                    (user['id'],))
                cur.execute("""INSERT INTO password_reset_codes
                    (user_id, purpose, code_hash, expires_at)
                    VALUES (%s, 'change', %s, now() + interval '10 minutes')""",
                    (user['id'], _email_hash_code(code)))
        channel = _deliver_auth_code(user['email'], code, 'change')
    except HTTPException:
        raise
    except Exception:
        with pool.connection() as conn:
            conn.execute("""UPDATE password_reset_codes SET consumed_at = now()
                WHERE user_id = %s AND purpose = 'change' AND consumed_at IS NULL""",
                (user['id'],))
        log.exception('Could not deliver password change code for user %s', user['id'])
        raise _problem(503, 'CODE_DELIVERY_UNAVAILABLE',
                       'No se pudo enviar el código. Configura Brevo, Resend o SMTP e inténtalo de nuevo.')
    return {'message': 'Si tienes acceso al correo vinculado, recibirás un código.',
            'channel': channel}


@app.post('/api/v1/auth/password/change-verify')
def verify_password_change_code(payload: PasswordChangeCodeVerifyRequest,
                                user: dict = Depends(current_user)) -> dict:
    try:
        password_hasher.verify(user['password_hash'], payload.current_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        raise _problem(400, 'CURRENT_PASSWORD_INVALID', 'La contraseña actual no es correcta.')
    with pool.connection() as conn:
        valid = _valid_reset_code(conn.cursor(), user['email'], payload.code,
                                  purpose='change', consume=False)
    if not valid:
        raise _problem(400, 'INVALID_CODE', 'El código es incorrecto o ya venció.')
    return {'valid': True}


@app.get('/api/v1/client/onboarding/options')
def client_onboarding_options(client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
        birth_date = conn.execute(
            "SELECT birth_date FROM client_profiles WHERE user_id = %s",
            (client['id'],)).fetchone()
        group = conn.execute("""SELECT g.plan_id, g.member_number,
                (SELECT count(*) FROM client_group_members gm WHERE gm.group_id = g.id) AS member_count
            FROM client_groups g JOIN client_group_members m ON m.group_id = g.id
            WHERE m.user_id = %s""", (client['id'],)).fetchone()
        plans = conn.execute("""SELECT id, name, price_mxn, duration_days, min_group_size, max_group_size
            FROM membership_plans WHERE gym_id = %s AND active ORDER BY created_at, name""",
            (client['gym_id'],)).fetchall()
        trainers = conn.execute("""SELECT u.id, u.first_name, u.last_name, tp.specialty
            FROM users u JOIN trainer_profiles tp ON tp.user_id = u.id
            WHERE u.gym_id = %s AND u.role = 'trainer' AND u.status = 'active'
            ORDER BY u.first_name, u.last_name""", (client['gym_id'],)).fetchall()
        assigned_trainer = conn.execute("""SELECT trainer_id FROM trainer_client_assignments
            WHERE client_id = %s AND ends_at IS NULL""", (client['id'],)).fetchone()
    result = {'plans': [{**p, 'id': str(p['id']), 'price_mxn': str(p['price_mxn']) if p['price_mxn'] is not None else None} for p in plans],
              'trainers': [{**t, 'id': str(t['id'])} for t in trainers]}
    result.update({'group_plan_id': str(group['plan_id']) if group and group['plan_id'] else None,
                   'birth_date': birth_date['birth_date'].isoformat()
                   if birth_date and birth_date['birth_date'] else None,
                   'group_member_number': group['member_number'] if group else None,
                   'group_member_count': group['member_count'] if group else 1,
                   'assigned_trainer_id': str(assigned_trainer['trainer_id'])
                   if assigned_trainer else None})
    return result


@app.get('/api/v1/client/trainers')
def client_trainers(client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
    conn.execute("""SELECT tca.trainer_id, concat_ws(' ', t.first_name, t.last_name) AS name
            FROM trainer_client_assignments tca JOIN users t ON t.id = tca.trainer_id
            WHERE tca.client_id = %s AND tca.ends_at IS NULL LIMIT 1""",
            (client['id'],)).fetchone()
        request = conn.execute("""SELECT r.id, r.trainer_id, r.status, r.requested_at,
                concat_ws(' ', t.first_name, t.last_name) AS trainer_name
            FROM client_trainer_requests r JOIN users t ON t.id = r.trainer_id
            WHERE r.client_id = %s AND r.status = 'pending'
            ORDER BY r.requested_at DESC LIMIT 1""", (client['id'],)).fetchone()
    return {
        'trainers': [{**row, 'id': str(row['id'])} for row in trainers],
        'assigned_trainer_id': str(assigned['trainer_id']) if assigned else None,
        'assigned_trainer_name': assigned['name'] if assigned else None,
        'pending_request': ({**request, 'id': str(request['id']),
                             'trainer_id': str(request['trainer_id']),
                             'requested_at': request['requested_at'].isoformat()}
                            if request else None),
    }


@app.post('/api/v1/client/trainer-requests', status_code=201)
def request_client_trainer(payload: TrainerRequestCreate,
                           client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            assigned = cur.execute("""SELECT 1 FROM trainer_client_assignments
                WHERE client_id = %s AND ends_at IS NULL""", (client['id'],)).fetchone()
            if assigned:
                raise _problem(409, 'TRAINER_ALREADY_ASSIGNED',
                               'Ya tienes entrenador asignado. Contacta al gimnasio si necesitas cambiarlo.')
            trainer = cur.execute("""SELECT id FROM users WHERE id = %s AND gym_id = %s
                AND role = 'trainer' AND status = 'active'""",
                (payload.trainer_id, client['gym_id'])).fetchone()
            if trainer is None:
                raise _problem(404, 'TRAINER_NOT_AVAILABLE', 'Ese entrenador ya no está disponible.')
            request = cur.execute("""SELECT id FROM client_trainer_requests
                WHERE client_id = %s AND status = 'pending' FOR UPDATE""",
                (client['id'],)).fetchone()
            if request:
                cur.execute("""UPDATE client_trainer_requests SET trainer_id = %s,
                    requested_at = now() WHERE id = %s""",
                    (payload.trainer_id, request['id']))
                request_id = request['id']
            else:
                request_id = cur.execute("""INSERT INTO client_trainer_requests
                    (gym_id, client_id, trainer_id) VALUES (%s, %s, %s) RETURNING id""",
                    (client['gym_id'], client['id'], payload.trainer_id)).fetchone()['id']
            cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                VALUES (%s, 'trainer_request', 'Nueva solicitud de entrenador', %s, %s)""",
                (payload.trainer_id,
                 f"{client['first_name']} {client['last_name']} quiere que seas su entrenador.",
                 Jsonb({'request_id': str(request_id), 'client_id': str(client['id'])})))
    return {'id': str(request_id), 'status': 'pending'}


@app.get('/api/v1/client/onboarding/routines')
def client_onboarding_routines(goal: Literal['Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza'],
                               days_per_week: int = Query(ge=3, le=6),
                               trainer_id: uuid.UUID | None = None,
                               client: dict = Depends(active_client)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT r.id, r.name, r.goal, r.days_per_week,
                concat_ws(' ', u.first_name, u.last_name) AS trainer_name,
                rp.id AS phase_id, rp.duration_weeks,
                (SELECT count(*) FROM routine_exercises re WHERE re.phase_id = rp.id AND re.active) AS exercise_count
            FROM routines r JOIN users u ON u.id = r.trainer_id
            JOIN routine_phases rp ON rp.routine_id = r.id AND rp.phase_number = 1 AND rp.status = 'published'
            WHERE r.gym_id = %s AND r.active AND u.status = 'active'
              AND r.goal = %s AND r.days_per_week = %s
              AND (%s::uuid IS NULL OR r.trainer_id = %s)
            ORDER BY r.updated_at DESC LIMIT 3""",
            (client['gym_id'], goal, days_per_week, trainer_id, trainer_id)).fetchall()
    return [{**row, 'id': str(row['id']), 'phase_id': str(row['phase_id'])} for row in rows]


@app.get('/api/v1/trainer/clients')
def trainer_clients(search: str = Query(default='', max_length=100),
                    trainer: dict = Depends(active_trainer)) -> list[dict]:
    term = f'%{search.strip()}%'
    with pool.connection() as conn:
        rows = conn.execute("""SELECT u.id, u.first_name, u.last_name, u.email, u.phone, u.member_number,
                p.name AS membership_plan, m.ends_on AS membership_ends_on,
                r.name AS routine_name, cp.goal, cp.days_per_week,
                (SELECT count(*) FROM attendance a WHERE a.client_id = u.id AND a.local_date >= (now() AT TIME ZONE g.timezone)::date - 6) AS attendance_7d
            FROM trainer_client_assignments tca
            JOIN users u ON u.id = tca.client_id AND u.status IN ('active', 'active_no_onboarding')
            JOIN gyms g ON g.id = u.gym_id
            LEFT JOIN client_profiles cp ON cp.user_id = u.id
            LEFT JOIN LATERAL (SELECT plan_id, ends_on FROM memberships WHERE client_id = u.id AND status = 'active' ORDER BY ends_on DESC LIMIT 1) m ON true
            LEFT JOIN membership_plans p ON p.id = m.plan_id
            LEFT JOIN LATERAL (SELECT r.name FROM client_routine_assignments cra JOIN routines r ON r.id = cra.routine_id WHERE cra.client_id = u.id AND cra.ended_at IS NULL LIMIT 1) r ON true
            WHERE tca.trainer_id = %s AND tca.ends_at IS NULL
              AND (concat_ws(' ', u.first_name, u.last_name) ILIKE %s OR u.email ILIKE %s)
            ORDER BY u.first_name, u.last_name""", (trainer['id'], term, term)).fetchall()
    return [{**row, 'id': str(row['id']), 'membership_ends_on': row['membership_ends_on'].isoformat() if row['membership_ends_on'] else None} for row in rows]


@app.get('/api/v1/trainer/assignment-requests')
def trainer_assignment_requests(trainer: dict = Depends(active_trainer)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT r.id, r.client_id, u.first_name, u.last_name,
                u.member_number, u.email, r.requested_at
            FROM client_trainer_requests r JOIN users u ON u.id = r.client_id
            WHERE r.trainer_id = %s AND r.status = 'pending' AND u.status IN ('active', 'active_no_onboarding')
            ORDER BY r.requested_at""", (trainer['id'],)).fetchall()
    return [{**row, 'id': str(row['id']), 'client_id': str(row['client_id']),
             'requested_at': row['requested_at'].isoformat()} for row in rows]


@app.post('/api/v1/trainer/assignment-requests/{request_id}/accept')
def accept_trainer_assignment_request(request_id: uuid.UUID,
                                      payload: TrainerRequestAcceptance,
                                      trainer: dict = Depends(active_trainer)) -> dict:
    if (payload.routine_id is None) != (payload.phase_id is None):
        raise _problem(422, 'INVALID_ROUTINE_SELECTION',
                       'Selecciona la rutina y la fase publicada.')
    with pool.connection() as conn:
        with conn.cursor() as cur:
            request = cur.execute("""SELECT id, client_id FROM client_trainer_requests
                WHERE id = %s AND trainer_id = %s AND status = 'pending' FOR UPDATE""",
                (request_id, trainer['id'])).fetchone()
            if request is None:
                raise _problem(404, 'TRAINER_REQUEST_NOT_FOUND', 'La solicitud ya fue atendida o no existe.')
            client = cur.execute("""SELECT id, first_name, last_name FROM users
                WHERE id = %s AND gym_id = %s AND role = 'client'
                  AND status IN ('active', 'active_no_onboarding') FOR UPDATE""",
                (request['client_id'], trainer['gym_id'])).fetchone()
            if client is None:
                raise _problem(404, 'CLIENT_NOT_AVAILABLE', 'El socio ya no está disponible.')
            current = cur.execute("""SELECT id FROM trainer_client_assignments
                WHERE client_id = %s AND ends_at IS NULL FOR UPDATE""",
                (client['id'],)).fetchone()
            if current:
                raise _problem(409, 'CLIENT_ALREADY_ASSIGNED', 'El socio ya tiene un entrenador asignado.')
            cur.execute("""INSERT INTO trainer_client_assignments
                (trainer_id, client_id, assigned_by) VALUES (%s, %s, %s)""",
                (trainer['id'], client['id'], trainer['id']))
            assigned_routine = None
            if payload.routine_id is not None:
                assigned_routine = cur.execute("""SELECT r.id, rp.id AS phase_id
                    FROM routines r JOIN routine_phases rp ON rp.routine_id = r.id
                    WHERE r.id = %s AND r.trainer_id = %s AND r.gym_id = %s
                      AND r.active AND rp.id = %s AND rp.status = 'published'""",
                    (payload.routine_id, trainer['id'], trainer['gym_id'],
                     payload.phase_id)).fetchone()
                if assigned_routine is None:
                    raise _problem(404, 'ROUTINE_NOT_AVAILABLE',
                                   'La rutina publicada ya no está disponible.')
                cur.execute("""UPDATE client_routine_assignments SET ended_at = now()
                    WHERE client_id = %s AND ended_at IS NULL""", (client['id'],))
                assignment = cur.execute("""INSERT INTO client_routine_assignments
                    (client_id, routine_id, current_phase_id, assigned_by)
                    VALUES (%s, %s, %s, %s) RETURNING id""",
                    (client['id'], assigned_routine['id'], assigned_routine['phase_id'],
                     trainer['id'])).fetchone()
                cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                    VALUES (%s, 'routine_assigned', 'Tu rutina está lista', %s, %s)""",
                    (client['id'], 'Tu entrenador te aceptó y te asignó una rutina. Ya puedes consultarla en Inicio.',
                     Jsonb({'routine_id': str(assigned_routine['id'])})))
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, subject_id, event_type, details)
                    VALUES (%s, %s, %s, 'routine_assigned', %s)""",
                    (trainer['gym_id'], trainer['id'], client['id'],
                     Jsonb({'routine_id': str(assigned_routine['id']),
                            'assignment_id': str(assignment['id'])})))
            cur.execute("UPDATE client_trainer_requests SET status = 'accepted', reviewed_at = now() WHERE id = %s",
                        (request_id,))
            cur.execute("""UPDATE client_trainer_requests SET status = 'cancelled', reviewed_at = now()
                WHERE client_id = %s AND id <> %s AND status = 'pending'""",
                (client['id'], request_id))
            cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                VALUES (%s, 'trainer_accepted', 'Entrenador asignado', %s, %s)""",
                (client['id'], f"{trainer['first_name']} {trainer['last_name']} aceptó tu solicitud.",
                 Jsonb({'trainer_id': str(trainer['id']),
                        'routine_id': str(assigned_routine['id']) if assigned_routine else None})))
    return {'request_id': str(request_id), 'clie 'accepted',
            'routine_id': str(assigned_routine['id']) if assigned_routine else None}


@app.post('/api/v1/trainer/assignment-requests/{request_id}/reject')
def reject_trainer_assignment_request(request_id: uuid.UUID,
                                      trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            request = cur.execute("""UPDATE client_trainer_requests SET status = 'rejected', reviewed_at = now()
                WHERE id = %s AND trainer_id = %s AND status = 'pending' RETURNING client_id""",
                (request_id, trainer['id'])).fetchone()
            if request is None:
                raise _problem(404, 'TRAINER_REQUEST_NOT_FOUND', 'La solicitud ya fue atendida o no existe.')
            cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                VALUES (%s, 'trainer_rejected', 'Solicitud de entrenador', %s, %s)""",
                (request['client_id'], f"{trainer['first_name']} {trainer['last_name']} no pudo aceptar tu solicitud. Puedes elegir otro entrenador.",
                 Jsonb({'trainer_id': str(trainer['id'])})))
    return {'request_id': str(request_id), 'status': 'rejected'}


@app.get('/api/v1/trainer/clients/{client_id}')
def trainer_client_detail(client_id: uuid.UUID,
                          trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        row = conn.execute("""SELECT u.id, u.first_name, u.last_name, u.email, u.phone,
                u.member_number, cp.goal, cp.experience_level, cp.days_per_week, cp.limitations,
                mp.name AS membership_plan, m.ends_on AS membership_ends_on,
                r.id AS routine_id, r.name AS routine_name, r.goal AS routine_goal,
                rp.phase_number, cra.phase_started_at,
                (SELECT count(*) FROM attendance a WHERE a.client_id = u.id) AS attendance_total,
                (SELECT count(*) FROM workout_completions wc WHERE wc.client_id = u.id) AS workouts_total,
                (SELECT count(*) FROM workout_completions wc WHERE wc.client_id = u.id
                    AND wc.workout_date >= (now() AT TIME ZONE g.timezone)::date - 6) AS workouts_7d,
                coalesce((SELECT jsonb_agg(a.local_date ORDER BY a.local_date)
                    FROM attendance a WHERE a.client_id = u.id
                    AND a.local_date >= (now() AT TIME ZONE g.timezone)::date - 6), '[]'::jsonb) AS attendance_7d_dates
            FROM users u JOIN gyms g ON g.id = u.gym_id
            JOIN trainer_client_assignments tca ON tca.client_id = u.id
                AND tca.trainer_id = %s AND tca.ends_at IS NULL
            LEFT JOIN client_profiles cp ON cp.user_id = u.id
            LEFT JOIN LATERAL (SELECT plan_id, ends_on FROM memberships WHERE client_id = u.id
                AND status = 'active' ORDER BY ends_on DESC LIMIT 1) m ON true
            LEFT JOIN membership_plans mp ON mp.id = m.plan_id
            LEFT JOIN LATERAL (SELECT routine_id, current_phase_id, phase_started_at
                FROM client_routine_assignments WHERE client_id = u.id AND ended_at IS NULL LIMIT 1) cra ON true
            LEFT JOIN routines r ON r.id = cra.routine_id
            LEFT JOIN routine_phases rp ON rp.id = cra.current_phase_id
            WHERE u.id = %s AND u.gym_id = %s AND u.role = 'client'
              AND u.status IN ('active', 'active_no_onboarding')""",
            (trainer['id'], client_id, trainer['gym_id'])).fetchone()
    if row is None:
        raise _problem(404, 'CLIENT_NOT_FOUND', 'No encontramos un cliente activo asignado a tu cuenta.')
    row['id'] = str(row['id'])
    if row['routine_id']:
        row['routine_id'] = str(row['routine_id'])
    if row['membership_ends_on']:
        row['membership_ends_on'] = row['membership_ends_on'].isoformat()
    if row['phase_started_at']:
        row['phase_started_at'] = row['phase_started_at'].isoformat()
    return row


@app.get('/api/v1/trainer/routines')
def trainer_routines(trainer: dict = Depends(active_trainer)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT r.id, r.name, r.goal, r.days_per_week, r.created_at,
                rp.id AS phase_id, rp.phase_number, rp.status AS phase_status,
                (SELECT count(*) FROM client_routine_assignments cra WHERE cra.routine_id = r.id AND cra.ended_at IS NULL) AS assigned_clients,
                (SELECT count(*) FROM routine_phases phases WHERE phases.routine_id = r.id) AS phases
            FROM routines r LEFT JOIN routine_phases rp ON rp.routine_id = r.id AND rp.phase_number = 1
            WHERE r.trainer_id = %s AND r.active ORDER BY r.updated_at DESC""",
            (trainer['id'],)).fetchall()
    return [{**row, 'id': str(row['id'])} for row in rows]


@app.get('/api/v1/trainer/exercises')
def trainer_exercise_catalog(search: str = Query(default='', max_length=80),
                             trainer: dict = Depends(active_trainer)) -> list[dict]:
    term = search.strip()
    pattern = f'%{term}%'
    with pool.connection() as conn:
        rows = conn.execute("""SELECT ec.id, ec.name, ec.muscle_group, ec.equipment, ec.instructions,
                tm.media_key, tm.media_mime, NULL::text AS media_url
            FROM exercise_catalog ec
            LEFT JOIN trainer_exercise_media tm
              ON tm.exercise_catalog_id = ec.id AND tm.trainer_id = %s
            WHERE ec.active AND (%s = '' OR ec.name ILIKE %s OR ec.muscle_group ILIKE %s OR ec.equipment ILIKE %s)
            ORDER BY ec.name LIMIT 50""",
            (trainer['id'], term, pattern, pattern, pattern)).fetchall()
    result = []
    for row in rows:
        item = {**row, 'id': str(row['id'])}
        if row.get('media_key'):
            try:
                item['media_url'] = presigned_exercise_media_url(row['media_key'])
            except (StorageNotConfigured, StorageReadError):
                item['media_url'] = None
        result.append(item)
    return result


@app.post('/api/v1/trainer/exercises', status_code=201)
def create_trainer_exercise(
    payload: TrainerExerciseCreate,
    trainer: dict = Depends(active_trainer),
) -> dict:
    name = payload.name.strip()
    if len(name) < 2:
        raise _problem(422, 'INVALID_EXERCISE_NAME', 'Escribe un nombre de al menos 2 caracteres.')
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                exercise = cur.execute("""INSERT INTO exercise_catalog
                        (name, muscle_group, equipment, instructions)
                    VALUES (%s, %s, %s, %s)
                    RETURNING id, name, muscle_group, equipment, instructions,
                        media_url, media_mime""",
                    (name, payload.muscle_group, payload.equipment,
                     payload.instructions.strip() if payload.instructions else None)).fetchone()
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, event_type, details)
                    VALUES (%s, %s, 'exercise_catalog_created', %s)""",
                    (trainer['gym_id'], trainer['id'], Jsonb({
                        'exercise_id': str(exercise['id']),
                        'name': exercise['name'],
                    })))
    except Exception as exc:
        if getattr(exc, 'sqlstate', None) == '23505':
            raise _problem(409, 'EXERCISE_NAME_EXISTS',
                           'Ya existe un ejercicio con ese nombre en el catálogo.')
        raise
    return {**exercise, 'id': str(exercise['id'])}


def _delete_exercise_catalog_entry(exercise_id: uuid.UUID, actor: dict) -> dict:
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                exercise = cur.execute("""SELECT id, name, media_key
                    FROM exercise_catalog WHERE id = %s AND active FOR UPDATE""",
                    (exercise_id,)).fetchone()
                if exercise is None:
                    raise _problem(404, 'EXERCISE_NOT_FOUND', 'No encontramos ese ejercicio.')
                media_rows = cur.execute("""SELECT media_key FROM trainer_exercise_media
                    WHERE exercise_catalog_id = %s""", (exercise_id,)).fetchall()
                media_keys = [row['media_key'] for row in media_rows]
                if exercise.get('media_key'):
                    media_keys.append(exercise['media_key'])
                cur.execute("DELETE FROM exercise_catalog WHERE id = %s", (exercise_id,))
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, event_type, details)
                    VALUES (%s, %s, 'exercise_catalog_deleted', %s)""",
                    (actor['gym_id'], actor['id'], Jsonb({
                        'exercise_id': str(exercise_id),
                        'name': exercise['name'],
                    })))
    except HTTPException:
        raise
    except Exception as exc:
        if getattr(exc, 'sqlstate', None) == '23503':
            raise _problem(
                409,
                'EXERCISE_IN_USE',
                'No se puede eliminar este ejercicio porque está asociado a otros registros.',
            ) from exc
        log.exception('Could not delete exercise catalog entry %s', exercise_id)
        raise
    for media_key in media_keys:
        try:
            delete_exercise_media(media_key)
        except Exception:
            log.exception('Could not delete removed exercise media from R2')
    return {'deleted': True, 'id': str(exercise_id), 'name': exercise['name']}


@app.delete('/api/v1/trainer/exercises/{exercise_id}')
def delete_trainer_exercise(
    exercise_id: uuid.UUID,
    trainer: dict = Depends(active_trainer),
) -> dict:
    return _delete_exercise_catalog_entry(exercise_id, trainer)


@app.post('/api/v1/trainer/exercises/{exercise_id}/media', status_code=200)
async def upload_trainer_exercise_media(
    exercise_id: uuid.UUID,
    video: UploadFile = File(...),
    trainer: dict = Depends(active_trainer),
) -> dict:
    allowed_types = {'video/mp4': 'mp4', 'video/webm': 'webm', 'video/quicktime': 'mov'}
    content_type = (video.content_type or '').split(';', 1)[0].lower()
    extension = allowed_types.get(content_type)
    if extension is None:
        raise _problem(415, 'UNSUPPORTED_VIDEO_TYPE', 'Usa un video MP4, MOV o WebM.')

    max_bytes = 50 * 1024 * 1024
    chunks: list[bytes] = []
    total = 0
    while chunk := await video.read(1024 * 1024):
        total += len(chunk)
        if total > max_bytes:
            raise _problem(413, 'VIDEO_TOO_LARGE', 'El video debe pesar máximo 50 MB.')
        chunks.append(chunk)
    if total == 0:
        raise _problem(400, 'EMPTY_VIDEO', 'El video está vacío. Graba otra toma.')

    key = f"exercise-media/{trainer['gym_id']}/{trainer['id']}/{exercise_id}/{uuid.uuid4().hex}.{extension}"
    old_key = None
    try:
        stored_key = put_exercise_media(key, b''.join(chunks), content_type)
        media_url = presigned_exercise_media_url(stored_key)
        with pool.connection() as conn:
            with conn.cursor() as cur:
                previous = cur.execute("""SELECT media_key FROM trainer_exercise_media
                    WHERE trainer_id = %s AND exercise_catalog_id = %s FOR UPDATE""",
                    (trainer['id'], exercise_id)).fetchone()
                exercise_exists = cur.execute("""SELECT id, name FROM exercise_catalog
                    WHERE id = %s AND active""", (exercise_id,)).fetchone()
                if exercise_exists is None:
                    raise _problem(404, 'EXERCISE_NOT_FOUND', 'No encontramos ese ejercicio.')
                old_key = previous['media_key'] if previous else None
                exercise = cur.execute("""INSERT INTO trainer_exercise_media
                        (trainer_id, exercise_catalog_id, media_key, media_mime)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (trainer_id, exercise_catalog_id) DO UPDATE
                    SET media_key = EXCLUDED.media_key, media_mime = EXCLUDED.media_mime,
                        updated_at = now()
                    RETURNING exercise_catalog_id AS id, media_key, media_mime""",
                    (trainer['id'], exercise_id, stored_key, content_type)).fetchone()
                if exercise is None:
                    raise _problem(404, 'EXERCISE_NOT_FOUND', 'No encontramos ese ejercicio.')
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, event_type, details)
                    VALUES (%s, %s, 'exercise_media_uploaded', %s)""",
                    (trainer['gym_id'], trainer['id'], Jsonb({
                        'exercise_id': str(exercise_id), 'trainer_id': str(trainer['id']),
                        'size_bytes': total,
                        'content_type': content_type,
                    })))
        if old_key and old_key != stored_key:
            try:
                delete_exercise_media(old_key)
            except Exception:
                log.exception('Could not delete replaced exercise media from R2')
        return {'id': str(exercise['id']), 'name': exercise_exists['name'],
                'media_key': stored_key, 'media_mime': content_type,
                'media_url': media_url, 'size_bytes': total}
    except HTTPException:
        try:
            delete_exercise_media(f'r2://{key}')
        except Exception:
            log.exception('Could not clean up rejected exercise media upload')
        raise
    except StorageNotConfigured as exc:
        raise _problem(503, 'EXERCISE_MEDIA_STORAGE_NOT_CONFIGURED', str(exc))
    except StorageWriteError as exc:
        raise _problem(503, 'EXERCISE_MEDIA_STORAGE_UNAVAILABLE', str(exc))
    except Exception:
        try:
            delete_exercise_media(f'r2://{key}')
        except Exception:
            log.exception('Could not clean up failed exercise media upload')
        raise


@app.get('/api/v1/admin/exercises')
def admin_exercise_catalog(search: str = Query(default='', max_length=80),
                           admin: dict = Depends(active_admin)) -> list[dict]:
    term = search.strip()
    pattern = f'%{term}%'
    with pool.connection() as conn:
        rows = conn.execute("""SELECT id, name, muscle_group, equipment, instructions,
                media_url, media_key, media_mime
            FROM exercise_catalog
            WHERE active AND (%s = '' OR name ILIKE %s OR muscle_group ILIKE %s OR equipment ILIKE %s)
            ORDER BY name LIMIT 100""",
            (term, pattern, pattern, pattern)).fetchall()
        trainer_media_rows = conn.execute("""SELECT tm.exercise_catalog_id,
                tm.trainer_id, tm.media_key, tm.media_mime,
                concat_ws(' ', u.first_name, u.last_name) AS trainer_name
            FROM trainer_exercise_media tm
            JOIN exercise_catalog ec ON ec.id = tm.exercise_catalog_id AND ec.active
            JOIN users u ON u.id = tm.trainer_id AND u.gym_id = %s
            WHERE ec.id = ANY(%s)
            ORDER BY u.first_name, u.last_name""",
            (admin['gym_id'], [row['id'] for row in rows])).fetchall() if rows else []
    media_by_exercise: dict[str, list[dict]] = {}
    for media in trainer_media_rows:
        item = {
            'trainer_id': str(media['trainer_id']),
            'trainer_name': media['trainer_name'],
            'media_mime': media['media_mime'],
            'media_url': None,
        }
        try:
            item['media_url'] = presigned_exercise_media_url(media['media_key'])
        except (StorageNotConfigured, StorageReadError):
            pass
        media_by_exercise.setdefault(str(media['exercise_catalog_id']), []).append(item)
    result = []
    for row in rows:
        item = {**row, 'id': str(row['id']),
                'trainer_media': media_by_exercise.get(str(row['id']), [])}
        if row.get('media_key'):
            try:
                item['media_url'] = presigned_exercise_media_url(row['media_key'])
            except (StorageNotConfigured, StorageReadError):
                item['media_url'] = None
        result.append(item)
    return result


@app.post('/api/v1/admin/exercises', status_code=201)
def create_admin_exercise(
    payload: TrainerExerciseCreate,
    admin: dict = Depends(active_admin),
) -> dict:
    name = payload.name.strip()
    if len(name) < 2:
        raise _problem(422, 'INVALID_EXERCISE_NAME', 'Escribe un nombre de al menos 2 caracteres.')
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                exercise = cur.execute("""INSERT INTO exercise_catalog
                        (name, muscle_group, equipment, instructions)
                    VALUES (%s, %s, %s, %s)
                    RETURNING id, name, muscle_group, equipment, instructions,
                        media_url, media_mime""",
                    (name, payload.muscle_group, payload.equipment,
                     payload.instructions.strip() if payload.instructions else None)).fetchone()
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, event_type, details)
                    VALUES (%s, %s, 'exercise_catalog_created', %s)""",
                    (admin['gym_id'], admin['id'], Jsonb({
                        'exercise_id': str(exercise['id']),
                        'name': exercise['name'],
                    })))
    except Exception as exc:
        if getattr(exc, 'sqlstate', None) == '23505':
            raise _problem(409, 'EXERCISE_NAME_EXISTS',
                           'Ya existe un ejercicio con ese nombre en el catálogo.')
        raise
    return {**exercise, 'id': str(exercise['id']