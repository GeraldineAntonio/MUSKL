from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import logging
import os
import secrets
import smtplib
import uuid
from contextlib import asynccontextmanager, suppress
from datetime import UTC, datetime, timedelta
from email.message import EmailMessage
from pathlib import Path
from typing import Annotated, Literal

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, EmailStr, Field, field_validator
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from psycopg.types.json import Jsonb

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
    """Permanently remove client records after the approved 90-day window."""
    with pool.connection() as conn:
        with conn.cursor() as cur:
            targets = cur.execute("""SELECT u.id, u.gym_id FROM users u
                WHERE u.role = 'client' AND u.status = 'deactivated'
                  AND u.reactivation_until <= now()
                  AND EXISTS (SELECT 1 FROM account_deletion_requests dr
                    WHERE dr.user_id = u.id AND dr.status = 'approved'
                      AND dr.resolved_at >= u.deactivated_at)
                ORDER BY u.reactivation_until LIMIT 100
                FOR UPDATE OF u SKIP LOCKED""").fetchall()
            if not targets:
                return 0
            user_ids = [row['id'] for row in targets]
            user_id_text = [str(user_id) for user_id in user_ids]

            # Remove client identifiers retained in JSON-only audit/notification
            # references. Relational audit and request references are SET NULL
            # by migration 004; personal activity rows cascade with the user.
            cur.execute("""UPDATE account_audit_events
                SET details = details - 'client_id' - 'assignment_id' - 'note'
                WHERE actor_id = ANY(%s) OR subject_id = ANY(%s)
                   OR details->>'client_id' = ANY(%s)""",
                (user_ids, user_ids, user_id_text))
            cur.execute("UPDATE account_deletion_requests SET note = NULL WHERE user_id = ANY(%s)",
                        (user_ids,))
            cur.execute("DELETE FROM notifications WHERE payload->>'client_id' = ANY(%s)",
                        (user_id_text,))
            deleted = cur.execute("DELETE FROM users WHERE id = ANY(%s) RETURNING gym_id",
                                  (user_ids,)).fetchall()
            by_gym: dict[uuid.UUID, int] = {}
            for row in deleted:
                by_gym[row['gym_id']] = by_gym.get(row['gym_id'], 0) + 1
            for gym_id, count in by_gym.items():
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, event_type, details)
                    VALUES (%s, 'account_data_purged', %s)""",
                    (gym_id, Jsonb({'accounts': count})))
            log.info('Purged %s expired client account(s)', len(deleted))
            return len(deleted)


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


class ClientRegistration(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = Field(default=None, max_length=30)
    password: str = Field(min_length=8, max_length=128)


class GroupMemberRegistration(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = Field(default=None, max_length=30)
    password: str = Field(min_length=8, max_length=128)


class ClientGroupRegistration(BaseModel):
    plan_id: uuid.UUID
    members: list[GroupMemberRegistration] = Field(min_length=1, max_length=49)


class AdminRegistration(BaseModel):
    first_name: str = Field(min_length=1, max_length=80)
    last_name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    phone: str | None = Field(default=None, max_length=30)
    password: str = Field(min_length=8, max_length=128)
    invite_token: str = Field(min_length=8, max_length=100)


class PasswordCodeRequest(BaseModel):
    email: EmailStr


class VerifyCodeRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')


class ResetPasswordRequest(VerifyCodeRequest):
    new_password: str = Field(min_length=8, max_length=128)


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
    limitations: str | None = Field(default=None, max_length=2000)
    routine_id: uuid.UUID | None = None


class ClientProfileUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=80)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=30)
    photo_data: str | None = Field(default=None, max_length=2_800_000)
    photo_mime: Literal['image/jpeg', 'image/png'] | None = None
    remove_photo: bool = False


class RoutineExerciseInput(BaseModel):
    catalog_id: uuid.UUID | None = None
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


class WorkoutCompletionRequest(BaseModel):
    duration_seconds: int | None = Field(default=None, ge=1, le=86400)


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
    new_password: str = Field(min_length=8, max_length=128)


class LoginRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=200)
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=200)


def _problem(status: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status, detail={'code': code, 'message': message})


def _email_hash_code(code: str) -> str:
    return hashlib.sha256(f'{JWT_SECRET}:{code}'.encode()).hexdigest()


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


def _create_user(cur, *, role: str, status: str, first_name: str, last_name: str,
                 email: str, phone: str | None, password: str, member_number: str | None = None) -> dict:
    user_id = uuid.uuid4()
    return cur.execute(
        """INSERT INTO users
           (id, gym_id, role, status, first_name, last_name, email, phone, member_number, password_hash)
           VALUES (%s, %s, %s::muskl_role, %s::account_status, %s, %s, %s, %s, %s, %s)
           RETURNING *""",
        (user_id, GYM_ID, role, status, first_name.strip(), last_name.strip(), email.lower(),
         phone.strip() if phone else None, member_number, password_hasher.hash(password))).fetchone()


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


def _deliver_reset_code(email: str, code: str) -> None:
    host = os.getenv('MUSKL_SMTP_HOST')
    if not host:
        if os.getenv('MUSKL_ENV', 'development') != 'development':
            raise RuntimeError('Configura SMTP para enviar códigos de recuperación.')
        log.info('DEV password reset code for %s: %s', email, code)
        return
    message = EmailMessage()
    message['Subject'] = 'Código para restablecer tu contraseña de MUSKL'
    message['From'] = os.environ['MUSKL_SMTP_FROM']
    message['To'] = email
    message.set_content(f'Tu código de recuperación es {code}. Vence en 10 minutos.')
    port = int(os.getenv('MUSKL_SMTP_PORT', '587'))
    with smtplib.SMTP(host, port, timeout=15) as server:
        if os.getenv('MUSKL_SMTP_STARTTLS', 'true').lower() == 'true':
            server.starttls()
        if os.getenv('MUSKL_SMTP_USER'):
            server.login(os.environ['MUSKL_SMTP_USER'], os.environ['MUSKL_SMTP_PASSWORD'])
        server.send_message(message)


def _deliver_notice_email(email: str, subject: str, body: str) -> None:
    """Best-effort account notice; internal notifications remain available without SMTP."""
    host = os.getenv('MUSKL_SMTP_HOST')
    if not host:
        log.warning('SMTP is not configured; account notice email was not sent to %s', email)
        return
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
    except Exception:
        log.exception('Could not send account notice email to %s', email)


@app.get('/health')
def health() -> dict:
    with pool.connection() as conn:
        conn.execute('SELECT 1')
    return {'status': 'ok', 'service': 'muskl-api'}


@app.post('/api/v1/auth/login')
def login(payload: LoginRequest) -> dict:
    identifier = payload.identifier.strip()
    password = payload.password
    with pool.connection() as conn:
        with conn.cursor() as cur:
            candidates = _find_login_candidates(cur, identifier)
            if not candidates:
                raise _problem(404, 'NOT_FOUND', 'No encontramos una cuenta con esos datos.')
            user = None
            for candidate in candidates:
                try:
                    if password_hasher.verify(candidate['password_hash'], password):
                        user = candidate
                        break
                except (VerifyMismatchError, VerificationError, InvalidHashError):
                    continue
            if user is None:
                raise _problem(401, 'INVALID_CREDENTIALS', 'Correo o contraseña incorrectos.')
            response = ({'user': _public_user(user)} if user['status'] == 'deactivated'
                        else _session_response(cur, user))
    return response


@app.post('/api/v1/auth/register/client', status_code=201)
def register_client(payload: ClientRegistration) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            existing = cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                                   (GYM_ID, str(payload.email).lower())).fetchone()
            if existing:
                raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado.')
            seq = cur.execute("SELECT nextval('member_number_seq') AS value").fetchone()['value']
            member_number = f'MSK-{seq:06d}'
            user = _create_user(cur, role='client', status='active_no_onboarding',
                                first_name=payload.first_name, last_name=payload.last_name,
                                email=str(payload.email), phone=payload.phone,
                                password=payload.password, member_number=member_number)
            cur.execute('INSERT INTO client_profiles (user_id) VALUES (%s)', (user['id'],))
            cur.execute('INSERT INTO client_groups (gym_id, member_number) VALUES (%s, %s) RETURNING id',
                        (GYM_ID, member_number))
            group = cur.fetchone()
            cur.execute('INSERT INTO client_group_members (group_id, user_id, is_primary) VALUES (%s, %s, true)',
                        (group['id'], user['id']))
            return _session_response(cur, user)


@app.post('/api/v1/auth/register/trainer', status_code=202)
def register_trainer(
    first_name: Annotated[str, Form(min_length=1, max_length=80)],
    last_name: Annotated[str, Form(min_length=1, max_length=100)],
    email: Annotated[EmailStr, Form()],
    password: Annotated[str, Form(min_length=8, max_length=128)],
    specialty: Annotated[str, Form(min_length=1, max_length=120)],
    phone: Annotated[str | None, Form(max_length=30)] = None,
    certification: UploadFile = File(...),
) -> dict:
    ext = Path(certification.filename or '').suffix.lower()
    allowed = {'.pdf': 'application/pdf', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg'}
    if ext not in allowed or certification.content_type != allowed[ext]:
        raise _problem(415, 'INVALID_CERTIFICATION', 'Adjunta una certificación PDF, PNG o JPG.')
    data = certification.file.read(10 * 1024 * 1024 + 1)
    if not data or len(data) > 10 * 1024 * 1024:
        raise _problem(413, 'CERTIFICATION_SIZE', 'El archivo debe pesar hasta 10 MB.')
    user_id = uuid.uuid4()
    relative_key = f'certifications/{user_id}/{uuid.uuid4()}{ext}'
    destination = UPLOAD_DIR / relative_key
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                if cur.execute('SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                               (GYM_ID, str(email).lower())).fetchone():
                    raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado.')
                user = _create_user(cur, role='trainer', status='pending', first_name=first_name,
                                    last_name=last_name, email=str(email), phone=phone,
                                    password=password)
                cur.execute('INSERT INTO trainer_profiles (user_id, specialty) VALUES (%s, %s)',
                            (user['id'], specialty.strip()))
                cur.execute('INSERT INTO trainer_certifications (trainer_id, title, storage_key) VALUES (%s, %s, %s)',
                            (user['id'], certification.filename or 'Certificación', relative_key))
                cur.execute('INSERT INTO account_audit_events (gym_id, subject_id, event_type) VALUES (%s, %s, %s)',
                            (GYM_ID, user['id'], 'trainer_registration_submitted'))
                _notify_admins_of_staff_request(cur, GYM_ID, user)
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    return {'status': 'pending', 'message': 'Solicitud enviada para revisión del gimnasio.'}


@app.post('/api/v1/auth/register/admin', status_code=202)
def register_admin(payload: AdminRegistration) -> dict:
    token_hash = hashlib.sha256(payload.invite_token.strip().encode()).hexdigest()
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
                                password=payload.password)
            cur.execute('UPDATE admin_invite_tokens SET used_at = now() WHERE id = %s', (invite['id'],))
            cur.execute('INSERT INTO account_audit_events (gym_id, subject_id, event_type) VALUES (%s, %s, %s)',
                        (GYM_ID, user['id'], 'admin_registration_submitted'))
            _notify_admins_of_staff_request(cur, GYM_ID, user)
    return {'status': 'pending', 'message': 'Solicitud enviada para revisión del gimnasio.'}


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
    return user


@app.post('/api/v1/client/group-members', status_code=201)
def register_client_group_members(payload: ClientGroupRegistration,
                                  client: dict = Depends(active_client)) -> dict:
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
                user = _create_user(cur, role='client', status='active_no_onboarding',
                    first_name=member.first_name, last_name=member.last_name, email=email,
                    phone=member.phone, password=member.password, member_number=group['member_number'])
                cur.execute('INSERT INTO client_profiles (user_id) VALUES (%s)', (user['id'],))
                cur.execute('INSERT INTO client_group_members (group_id, user_id) VALUES (%s, %s)',
                            (group['id'], user['id']))
            cur.execute('UPDATE client_groups SET plan_id = %s WHERE id = %s',
                        (payload.plan_id, group['id']))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'client_group_registered', %s)",
                        (client['gym_id'], client['id'], Jsonb({'plan_id': str(plan['id']), 'member_count': target_size})))
    return {'member_number': group['member_number'], 'member_count': target_size, 'created': True}


def onboarded_client(user: dict = Depends(active_client)) -> dict:
    if user['status'] != 'active':
        raise _problem(403, 'ONBOARDING_REQUIRED', 'Completa el onboarding antes de usar el módulo de cliente.')
    return user


def active_trainer(user: dict = Depends(current_user)) -> dict:
    if user['role'] != 'trainer' or user['status'] != 'active':
        raise _problem(403, 'TRAINER_REQUIRED', 'Esta opción requiere una cuenta entrenador activa.')
    return user


@app.get('/api/v1/auth/me')
def me(user: dict = Depends(current_user)) -> dict:
    return {'user': _public_user(user)}


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
                tp.specialty, tp.bio, tp.notification_preferences,
                coalesce((SELECT jsonb_agg(jsonb_build_object('id', tc.id, 'title', tc.title,
                    'verified_at', tc.verified_at) ORDER BY tc.created_at)
                    FROM trainer_certifications tc WHERE tc.trainer_id = u.id), '[]'::jsonb) AS certifications
            FROM users u JOIN trainer_profiles tp ON tp.user_id = u.id WHERE u.id = %s""",
            (trainer['id'],)).fetchone()
    return profile


@app.patch('/api/v1/trainer/profile')
def update_trainer_profile(payload: TrainerProfileUpdate,
                           trainer: dict = Depends(active_trainer)) -> dict:
    allowed_preferences = {'client_activity', 'routine_expiry', 'daily_reminder'}
    preferences = {key: payload.notification_preferences.get(key, False)
                   for key in allowed_preferences}
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""UPDATE users SET first_name = %s, last_name = %s,
                    email = %s, phone = %s, updated_at = now() WHERE id = %s""",
                    (payload.first_name.strip(), payload.last_name.strip(),
                     str(payload.email).lower(), payload.phone.strip() if payload.phone else None,
                     trainer['id']))
                cur.execute("""UPDATE trainer_profiles SET specialty = %s, bio = %s,
                    notification_preferences = %s, updated_at = now() WHERE user_id = %s""",
                    (payload.specialty.strip() if payload.specialty else None,
                     payload.bio.strip() if payload.bio else None, Jsonb(preferences), trainer['id']))
                cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'trainer_profile_updated', %s)",
                    (trainer['gym_id'], trainer['id'], Jsonb({'email': str(payload.email)})))
    except Exception as exc:
        constraint = getattr(getattr(exc, 'diag', None), 'constraint_name', '')
        if constraint == 'users_email_per_gym_uq':
            raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado en el gimnasio.')
        raise
    return trainer_profile(trainer)


@app.patch('/api/v1/auth/password')
def change_password(payload: PasswordChangeRequest,
                    user: dict = Depends(current_user)) -> dict:
    try:
        password_hasher.verify(user['password_hash'], payload.current_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        raise _problem(400, 'CURRENT_PASSWORD_INVALID', 'La contraseña actual no es correcta.')
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute('UPDATE users SET password_hash = %s, updated_at = now() WHERE id = %s',
                (password_hasher.hash(payload.new_password), user['id']))
            cur.execute('UPDATE auth_sessions SET revoked_at = now() WHERE user_id = %s AND id <> %s AND revoked_at IS NULL',
                (user['id'], user['session_id']))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type) VALUES (%s, %s, 'password_changed')",
                (user['gym_id'], user['id']))
    return {'status': 'updated'}


@app.get('/api/v1/client/onboarding/options')
def client_onboarding_options(client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
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
    result = {'plans': [{**p, 'id': str(p['id']), 'price_mxn': str(p['price_mxn']) if p['price_mxn'] is not None else None} for p in plans],
              'trainers': [{**t, 'id': str(t['id'])} for t in trainers]}
    result.update({'group_plan_id': str(group['plan_id']) if group and group['plan_id'] else None,
                   'group_member_number': group['member_number'] if group else None,
                   'group_member_count': group['member_count'] if group else 1})
    return result


@app.get('/api/v1/client/onboarding/routines')
def client_onboarding_routines(goal: Literal['Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza'],
                               days_per_week: int = Query(ge=3, le=6),
                               trainer_id: uuid.UUID | None = None,
                               client: dict = Depends(active_client)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT r.id, r.name, r.goal, r.days_per_week,
                concat_ws(' ', u.first_name, u.last_name) AS trainer_name,
                rp.id AS phase_id, rp.duration_weeks,
                (SELECT count(*) FROM routine_exercises re WHERE re.phase_id = rp.id) AS exercise_count
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
            JOIN users u ON u.id = tca.client_id AND u.status = 'active'
            JOIN gyms g ON g.id = u.gym_id
            LEFT JOIN client_profiles cp ON cp.user_id = u.id
            LEFT JOIN LATERAL (SELECT plan_id, ends_on FROM memberships WHERE client_id = u.id AND status = 'active' ORDER BY ends_on DESC LIMIT 1) m ON true
            LEFT JOIN membership_plans p ON p.id = m.plan_id
            LEFT JOIN LATERAL (SELECT r.name FROM client_routine_assignments cra JOIN routines r ON r.id = cra.routine_id WHERE cra.client_id = u.id AND cra.ended_at IS NULL LIMIT 1) r ON true
            WHERE tca.trainer_id = %s AND tca.ends_at IS NULL
              AND (concat_ws(' ', u.first_name, u.last_name) ILIKE %s OR u.member_number ILIKE %s)
            ORDER BY u.first_name, u.last_name""", (trainer['id'], term, term)).fetchall()
    return [{**row, 'id': str(row['id']), 'membership_ends_on': row['membership_ends_on'].isoformat() if row['membership_ends_on'] else None} for row in rows]


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
            WHERE u.id = %s AND u.gym_id = %s AND u.role = 'client' AND u.status = 'active'""",
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
        rows = conn.execute("""SELECT id, name, muscle_group, equipment, instructions, media_url
            FROM exercise_catalog
            WHERE active AND (%s = '' OR name ILIKE %s OR muscle_group ILIKE %s OR equipment ILIKE %s)
            ORDER BY name LIMIT 50""",
            (term, pattern, pattern, pattern)).fetchall()
    return [{**row, 'id': str(row['id'])} for row in rows]


def _resolve_catalog_exercise(
    cur, exercise: RoutineExerciseInput
) -> tuple[uuid.UUID | None, str, str | None, str | None]:
    if exercise.catalog_id is None:
        return None, exercise.name.strip(), None, None
    catalog = cur.execute("""SELECT id, name, media_url, instructions FROM exercise_catalog
        WHERE id = %s AND active""", (exercise.catalog_id,)).fetchone()
    if catalog is None:
        raise _problem(422, 'EXERCISE_NOT_AVAILABLE', 'El ejercicio elegido ya no está disponible.')
    return catalog['id'], catalog['name'], catalog['media_url'], catalog['instructions']


@app.post('/api/v1/trainer/routines', status_code=201)
def create_trainer_routine(payload: RoutineCreateRequest,
                           trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            routine = cur.execute("""INSERT INTO routines (gym_id, trainer_id, name, goal, days_per_week)
                VALUES (%s, %s, %s, %s, %s) RETURNING id, name, goal, days_per_week""",
                (trainer['gym_id'], trainer['id'], payload.name.strip(), payload.goal, len(payload.days))).fetchone()
            phase = cur.execute("INSERT INTO routine_phases (routine_id, phase_number, name, duration_weeks, status) VALUES (%s, 1, 'Fase 1', 8, 'draft') RETURNING id",
                                (routine['id'],)).fetchone()
            for day_number in payload.days:
                for position, exercise in enumerate(payload.exercises, start=1):
                    catalog_id, exercise_name, media_url, instructions = _resolve_catalog_exercise(cur, exercise)
                    cur.execute("""INSERT INTO routine_exercises
                        (phase_id, day_number, position, exercise_catalog_id, name, sets, reps,
                         rest_seconds, media_url, instructions)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                        (phase['id'], day_number, position, catalog_id, exercise_name,
                         exercise.sets, exercise.reps, exercise.rest_seconds, media_url, instructions))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, %s, %s)",
                        (trainer['gym_id'], trainer['id'], 'routine_created', Jsonb({'routine_id': str(routine['id']), 'phase_id': str(phase['id'])})))
    return {**routine, 'id': str(routine['id']), 'phase_id': str(phase['id']), 'status': 'draft'}


@app.get('/api/v1/trainer/routines/{routine_id}')
def trainer_routine_detail(routine_id: uuid.UUID,
                           trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        routine = conn.execute("""SELECT id, name, goal, days_per_week FROM routines
            WHERE id = %s AND trainer_id = %s AND active""",
            (routine_id, trainer['id'])).fetchone()
        if routine is None:
            raise _problem(404, 'ROUTINE_NOT_FOUND', 'No encontramos esa rutina.')
        phases = conn.execute("""SELECT rp.id, rp.phase_number, rp.name, rp.duration_weeks,
                rp.status, rp.published_at,
                (SELECT count(*) FROM routine_exercises e WHERE e.phase_id = rp.id) AS exercise_count
            FROM routine_phases rp WHERE rp.routine_id = %s ORDER BY rp.phase_number""",
            (routine_id,)).fetchall()
        exercises = conn.execute("""SELECT e.id, e.phase_id, rp.phase_number, e.day_number,
                e.position, e.name, e.sets, e.reps, e.rest_seconds, e.instructions
            FROM routine_exercises e JOIN routine_phases rp ON rp.id = e.phase_id
            WHERE rp.routine_id = %s ORDER BY rp.phase_number, e.day_number, e.position""",
            (routine_id,)).fetchall()
    routine['id'] = str(routine['id'])
    for phase in phases:
        phase['id'] = str(phase['id'])
        phase['published_at'] = phase['published_at'].isoformat() if phase['published_at'] else None
    for exercise in exercises:
        exercise['id'] = str(exercise['id'])
        exercise['phase_id'] = str(exercise['phase_id'])
    return {**routine, 'phases': phases, 'exercises': exercises}


@app.post('/api/v1/trainer/routines/{routine_id}/phases', status_code=201)
def create_routine_phase(routine_id: uuid.UUID, payload: RoutinePhaseCreateRequest,
                         trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            routine = cur.execute("SELECT id, days_per_week FROM routines WHERE id = %s AND trainer_id = %s AND active FOR UPDATE",
                                  (routine_id, trainer['id'])).fetchone()
            if routine is None:
                raise _problem(404, 'ROUTINE_NOT_FOUND', 'No encontramos esa rutina.')
            if len(payload.days) != routine['days_per_week']:
                raise _problem(422, 'ROUTINE_DAYS_MISMATCH', 'La nueva fase debe conservar los días semanales de la rutina.')
            latest = cur.execute("SELECT phase_number, status FROM routine_phases WHERE routine_id = %s ORDER BY phase_number DESC LIMIT 1 FOR UPDATE",
                                 (routine_id,)).fetchone()
            if latest is None or latest['status'] != 'published':
                raise _problem(409, 'PREVIOUS_PHASE_NOT_PUBLISHED', 'Publica la fase actual antes de crear la siguiente.')
            number = latest['phase_number'] + 1
            phase = cur.execute("""INSERT INTO routine_phases (routine_id, phase_number, name, duration_weeks)
                VALUES (%s, %s, %s, 8) RETURNING id, phase_number, name, duration_weeks, status""",
                (routine_id, number, payload.name.strip())).fetchone()
            for day in payload.days:
                for position, exercise in enumerate(payload.exercises, 1):
                    catalog_id, exercise_name, media_url, instructions = _resolve_catalog_exercise(cur, exercise)
                    cur.execute("""INSERT INTO routine_exercises
                        (phase_id, day_number, position, exercise_catalog_id, name, sets, reps,
                         rest_seconds, media_url, instructions)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                        (phase['id'], day, position, catalog_id, exercise_name, exercise.sets,
                         exercise.reps, exercise.rest_seconds, media_url, instructions))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'routine_phase_created', %s)",
                (trainer['gym_id'], trainer['id'], Jsonb({'routine_id': str(routine_id), 'phase_id': str(phase['id']), 'phase_number': number})))
    return {**phase, 'id': str(phase['id'])}


@app.post('/api/v1/trainer/routines/{routine_id}/phases/{phase_id}/publish')
def publish_routine_phase(routine_id: uuid.UUID, phase_id: uuid.UUID,
                          trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            phase = cur.execute("""SELECT rp.id, rp.phase_number, rp.status,
                    (SELECT max(previous.phase_number) FROM routine_phases previous
                      WHERE previous.routine_id = r.id AND previous.status = 'published') AS last_published
                FROM routines r JOIN routine_phases rp ON rp.routine_id = r.id
                WHERE r.id = %s AND r.trainer_id = %s AND r.active AND rp.id = %s
                FOR UPDATE OF rp""", (routine_id, trainer['id'], phase_id)).fetchone()
            if phase is None:
                raise _problem(404, 'PHASE_NOT_FOUND', 'No encontramos esa fase.')
            if phase['status'] == 'published':
                return {'routine_id': str(routine_id), 'phase_id': str(phase_id), 'status': 'published'}
            if phase['last_published'] is None or phase['phase_number'] != phase['last_published'] + 1:
                raise _problem(409, 'PHASE_ORDER_INVALID', 'Debes publicar las fases en orden.')
            has_exercises = cur.execute('SELECT EXISTS (SELECT 1 FROM routine_exercises WHERE phase_id = %s) AS has_exercises',
                                        (phase_id,)).fetchone()['has_exercises']
            if not has_exercises:
                raise _problem(409, 'PHASE_EMPTY', 'Agrega ejercicios antes de publicar la fase.')
            cur.execute("UPDATE routine_phases SET status = 'published', published_at = now() WHERE id = %s",
                        (phase_id,))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'routine_phase_published', %s)",
                (trainer['gym_id'], trainer['id'], Jsonb({'routine_id': str(routine_id), 'phase_id': str(phase_id), 'phase_number': phase['phase_number']})))
    return {'routine_id': str(routine_id), 'phase_id': str(phase_id), 'status': 'published'}


@app.post('/api/v1/trainer/routines/{routine_id}/publish')
def publish_trainer_routine(routine_id: uuid.UUID,
                            trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            phase = cur.execute("""SELECT rp.id, rp.status FROM routine_phases rp
                JOIN routines r ON r.id = rp.routine_id
                WHERE r.id = %s AND r.trainer_id = %s AND r.active AND rp.phase_number = 1
                FOR UPDATE OF rp""", (routine_id, trainer['id'])).fetchone()
            if phase is None:
                raise _problem(404, 'routine_not_found', 'No se encontró la rutina.')
            if phase['status'] != 'published':
                cur.execute("UPDATE routine_phases SET status = 'published', published_at = now() WHERE id = %s",
                            (phase['id'],))
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'routine_published', %s)",
                        (trainer['gym_id'], trainer['id'], Jsonb({'routine_id': str(routine_id), 'phase_id': str(phase['id'])})))
    return {'routine_id': str(routine_id), 'phase_id': str(phase['id']), 'status': 'published'}


@app.post('/api/v1/trainer/routines/{routine_id}/assign')
def assign_trainer_routine(routine_id: uuid.UUID, payload: RoutineAssignmentRequest,
                           trainer: dict = Depends(active_trainer)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            row = cur.execute("""SELECT r.id AS routine_id, rp.id AS phase_id, u.id AS client_id
                FROM routines r JOIN routine_phases rp ON rp.routine_id = r.id
                JOIN users u ON u.id = %s AND u.gym_id = r.gym_id AND u.role = 'client' AND u.status = 'active'
                JOIN trainer_client_assignments tca ON tca.client_id = u.id AND tca.trainer_id = r.trainer_id AND tca.ends_at IS NULL
                WHERE r.id = %s AND r.trainer_id = %s AND r.active AND rp.id = %s AND rp.status = 'published'
                FOR UPDATE OF u""", (payload.client_id, routine_id, trainer['id'], payload.phase_id)).fetchone()
            if row is None:
                raise _problem(404, 'assignment_not_allowed', 'Rutina publicada o cliente asignado no encontrado.')
            cur.execute("UPDATE client_routine_assignments SET ended_at = now() WHERE client_id = %s AND ended_at IS NULL",
                        (row['client_id'],))
            assignment = cur.execute("""INSERT INTO client_routine_assignments
                (client_id, routine_id, current_phase_id, assigned_by)
                VALUES (%s, %s, %s, %s) RETURNING id""",
                (row['client_id'], row['routine_id'], row['phase_id'], trainer['id'])).fetchone()
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, event_type, details) VALUES (%s, %s, 'routine_assigned', %s)",
                        (trainer['gym_id'], trainer['id'], Jsonb({'client_id': str(row['client_id']), 'routine_id': str(row['routine_id']), 'assignment_id': str(assignment['id'])})))
    return {'assignment_id': str(assignment['id']), 'client_id': str(row['client_id']), 'routine_id': str(row['routine_id'])}


@app.post('/api/v1/client/onboarding')
def complete_client_onboarding(payload: ClientOnboardingRequest,
                               client: dict = Depends(active_client)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            locked = cur.execute("SELECT id, role, status FROM users WHERE id = %s AND gym_id = %s FOR UPDATE",
                                 (client['id'], client['gym_id'])).fetchone()
            if locked is None or locked['role'] != 'client' or locked['status'] != 'active_no_onboarding':
                raise _problem(409, 'ONBOARDING_ALREADY_COMPLETED', 'El onboarding ya se completó o la cuenta no está disponible.')
            group = cur.execute("""SELECT g.id, g.plan_id FROM client_groups g
                JOIN client_group_members m ON m.group_id = g.id
                WHERE m.user_id = %s FOR UPDATE OF g""", (client['id'],)).fetchone()
            chosen_plan_id = group['plan_id'] if group and group['plan_id'] else payload.plan_id
            if group and group['plan_id'] and payload.plan_id != group['plan_id']:
                raise _problem(409, 'GROUP_PLAN_LOCKED', 'Todos los integrantes deben conservar el plan del grupo.')
            plan = cur.execute("SELECT id, duration_days FROM membership_plans WHERE id = %s AND gym_id = %s AND active",
                               (chosen_plan_id, client['gym_id'])).fetchone()
            if plan is None:
                raise _problem(404, 'PLAN_NOT_FOUND', 'Elige un plan de membresía disponible.')
            if plan['duration_days'] is None:
                raise _problem(409, 'PLAN_NOT_CONFIGURED', 'Este plan todavía no tiene una duración configurada.')
            selected_trainer_id = payload.trainer_id
            selected_routine = None
            if payload.routine_id is not None:
                selected_routine = cur.execute("""SELECT r.id, r.trainer_id, rp.id AS phase_id
                    FROM routines r JOIN users t ON t.id = r.trainer_id AND t.status = 'active'
                    JOIN routine_phases rp ON rp.routine_id = r.id AND rp.phase_number = 1 AND rp.status = 'published'
                    WHERE r.id = %s AND r.gym_id = %s AND r.active AND r.goal = %s
                      AND r.days_per_week = %s AND (%s::uuid IS NULL OR r.trainer_id = %s)""",
                    (payload.routine_id, client['gym_id'], payload.goal, payload.days_per_week,
                     selected_trainer_id, selected_trainer_id)).fetchone()
                if selected_routine is None:
                    raise _problem(409, 'ROUTINE_NOT_AVAILABLE', 'La rutina ya no está disponible para tus preferencias.')
                selected_trainer_id = selected_routine['trainer_id']
            if selected_trainer_id is not None:
                trainer = cur.execute("SELECT id FROM users WHERE id = %s AND gym_id = %s AND role = 'trainer' AND status = 'active'",
                                      (selected_trainer_id, client['gym_id'])).fetchone()
                if trainer is None:
                    raise _problem(404, 'TRAINER_NOT_AVAILABLE', 'El entrenador seleccionado ya no está disponible.')
            starts = cur.execute("SELECT (now() AT TIME ZONE timezone)::date AS date FROM gyms WHERE id = %s",
                                 (client['gym_id'],)).fetchone()['date']
            cur.execute("INSERT INTO memberships (client_id, plan_id, starts_on, ends_on, registered_by) VALUES (%s, %s, %s, %s, %s)",
                        (client['id'], plan['id'], starts, starts + timedelta(days=plan['duration_days'] - 1), client['id']))
            if group and group['plan_id'] is None:
                cur.execute('UPDATE client_groups SET plan_id = %s WHERE id = %s',
                            (plan['id'], group['id']))
            if selected_trainer_id is not None:
                cur.execute("INSERT INTO trainer_client_assignments (trainer_id, client_id, assigned_by) VALUES (%s, %s, %s)",
                            (selected_trainer_id, client['id'], client['id']))
            if selected_routine is not None:
                cur.execute("""INSERT INTO client_routine_assignments
                    (client_id, routine_id, current_phase_id, assigned_by)
                    VALUES (%s, %s, %s, %s)""",
                    (client['id'], selected_routine['id'], selected_routine['phase_id'], client['id']))
            cur.execute("UPDATE client_profiles SET goal = %s, experience_level = %s, days_per_week = %s, limitations = %s, onboarding_completed_at = now(), updated_at = now() WHERE user_id = %s",
                        (payload.goal, payload.experience_level, payload.days_per_week, payload.limitations, client['id']))
            updated = cur.execute("UPDATE users SET status = 'active' WHERE id = %s RETURNING *", (client['id'],)).fetchone()
            cur.execute("INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type, details) VALUES (%s, %s, %s, %s, %s)",
                        (client['gym_id'], client['id'], client['id'], 'client_onboarding_completed', Jsonb({'plan_id': str(plan['id']), 'trainer_id': str(selected_trainer_id) if selected_trainer_id else None, 'routine_id': str(selected_routine['id']) if selected_routine else None})))
    return {'user': _public_user(updated)}


def _advance_due_client_phase(conn, client_id: uuid.UUID) -> bool:
    with conn.cursor() as cur:
        current = cur.execute("""SELECT cra.id AS assignment_id, cra.current_phase_id,
                cra.phase_started_at, r.id AS routine_id, r.name AS routine_name,
                r.trainer_id, rp.phase_number, u.gym_id
            FROM client_routine_assignments cra
            JOIN routines r ON r.id = cra.routine_id AND r.active
            JOIN routine_phases rp ON rp.id = cra.current_phase_id AND rp.status = 'published'
            JOIN users u ON u.id = cra.client_id
            WHERE cra.client_id = %s AND cra.ended_at IS NULL
              AND cra.phase_started_at <= now() - interval '8 weeks'
            ORDER BY cra.started_at DESC LIMIT 1 FOR UPDATE OF cra""",
            (client_id,)).fetchone()
        if current is None:
            return False
        next_phase = cur.execute("""SELECT id, phase_number, name FROM routine_phases
            WHERE routine_id = %s AND phase_number = %s AND status = 'published'""",
            (current['routine_id'], current['phase_number'] + 1)).fetchone()
        if next_phase is None:
            enabled = cur.execute("SELECT coalesce((notification_preferences->>'routine_expiry')::boolean, true) AS enabled FROM trainer_profiles WHERE user_id = %s",
                                  (current['trainer_id'],)).fetchone()
            if enabled and enabled['enabled']:
                prior = cur.execute("""SELECT 1 FROM notifications WHERE user_id = %s
                    AND kind = 'routine_phase_due' AND payload->>'assignment_id' = %s LIMIT 1""",
                    (current['trainer_id'], str(current['assignment_id']))).fetchone()
                if prior is None:
                    cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                        VALUES (%s, 'routine_phase_due', 'Fase próxima por publicar', %s, %s)""",
                        (current['trainer_id'],
                         f"{current['routine_name']} ya cumplió ocho semanas para un cliente.",
                         Jsonb({'assignment_id': str(current['assignment_id']), 'client_id': str(client_id),
                                'routine_id': str(current['routine_id']), 'phase_number': current['phase_number'] + 1})))
            return False
        cur.execute("UPDATE client_routine_assignments SET current_phase_id = %s, phase_started_at = now() WHERE id = %s",
                    (next_phase['id'], current['assignment_id']))
        cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
            VALUES (%s, 'new_phase_available', 'Nueva fase disponible', %s, %s)""",
            (client_id,
             f"Tu entrenador publicó {next_phase['name']} para {current['routine_name']}.",
             Jsonb({'routine_id': str(current['routine_id']), 'phase_id': str(next_phase['id']),
                    'phase_number': next_phase['phase_number'], 'routine_name': current['routine_name']})))
        return True


def _process_due_routine_phases() -> int:
    """Advance eligible assignments and notify trainers even if clients stay offline."""
    with pool.connection() as conn:
        client_ids = conn.execute("""SELECT DISTINCT cra.client_id
            FROM client_routine_assignments cra
            JOIN users u ON u.id = cra.client_id AND u.status = 'active'
            JOIN routine_phases rp ON rp.id = cra.current_phase_id AND rp.status = 'published'
            WHERE cra.ended_at IS NULL
              AND cra.phase_started_at <= now() - interval '8 weeks'
            ORDER BY cra.client_id LIMIT 500""").fetchall()
        advanced = 0
        for row in client_ids:
            if _advance_due_client_phase(conn, row['client_id']):
                advanced += 1
        return advanced


def _deliver_trainer_daily_reminders() -> int:
    """Create one in-app morning reminder per trainer and local gym date."""
    created = 0
    with pool.connection() as conn:
        trainers = conn.execute("""SELECT u.id, g.id AS gym_id, g.timezone,
                (now() AT TIME ZONE g.timezone)::date AS local_date
            FROM users u JOIN trainer_profiles tp ON tp.user_id = u.id
            JOIN gyms g ON g.id = u.gym_id
            WHERE u.role = 'trainer' AND u.status = 'active'
              AND coalesce((tp.notification_preferences->>'daily_reminder')::boolean, false)
              AND extract(hour FROM now() AT TIME ZONE g.timezone) >= 8""").fetchall()
        with conn.cursor() as cur:
            for trainer in trainers:
                local_date = trainer['local_date']
                already_sent = cur.execute("""SELECT 1 FROM notifications
                    WHERE user_id = %s AND kind = 'daily_reminder'
                      AND payload->>'local_date' = %s LIMIT 1""",
                    (trainer['id'], local_date.isoformat())).fetchone()
                if already_sent:
                    continue
                pending = cur.execute("""SELECT count(DISTINCT c.id) AS total
                    FROM trainer_client_assignments tca
                    JOIN users c ON c.id = tca.client_id AND c.status = 'active'
                    JOIN client_routine_assignments cra ON cra.client_id = c.id AND cra.ended_at IS NULL
                    JOIN routine_exercises re ON re.phase_id = cra.current_phase_id
                      AND re.day_number = extract(isodow FROM %s::date)::integer
                    WHERE tca.trainer_id = %s AND tca.ends_at IS NULL
                      AND NOT EXISTS (SELECT 1 FROM workout_completions wc
                        WHERE wc.client_id = c.id AND wc.phase_id = cra.current_phase_id
                          AND wc.workout_date = %s)""",
                    (local_date, trainer['id'], local_date)).fetchone()['total']
                if pending == 0:
                    continue
                cur.execute("""INSERT INTO notifications (user_id, kind, title, body, payload)
                    VALUES (%s, 'daily_reminder', 'Seguimiento de hoy', %s, %s)""",
                    (trainer['id'],
                     f'Tienes {pending} cliente(s) con sesión pendiente para hoy.',
                     Jsonb({'local_date': local_date.isoformat(), 'pending_clients': pending})))
                created += 1
    return created


@app.get('/api/v1/client/dashboard')
def client_dashboard(client: dict = Depends(onboarded_client)) -> dict:
    with pool.connection() as conn:
        _advance_due_client_phase(conn, client['id'])
        row = conn.execute("""SELECT u.first_name, u.last_name, u.member_number, u.email, u.phone, cp.goal,
                cp.profile_photo, cp.profile_photo_mime,
                g.timezone, p.name AS plan_name, m.ends_on AS membership_ends_on,
                concat_ws(' ', t.first_name, t.last_name) AS trainer_name,
                r.name AS routine_name, cra.current_phase_id, rp.phase_number,
                cra.phase_started_at, (now() AT TIME ZONE g.timezone)::date AS today,
                deletion_request.status AS deletion_request_status,
                deletion_request.requested_at AS deletion_requested_at,
                COALESCE((SELECT count(*) FROM attendance a WHERE a.client_id = u.id), 0) AS attendance_total,
                COALESCE((SELECT count(*) FROM workout_completions wc WHERE wc.client_id = u.id AND wc.workout_date >= (now() AT TIME ZONE g.timezone)::date - 6), 0) AS workouts_7d
            FROM users u JOIN gyms g ON g.id = u.gym_id
            LEFT JOIN client_profiles cp ON cp.user_id = u.id
            LEFT JOIN LATERAL (SELECT plan_id, ends_on FROM memberships WHERE client_id = u.id AND status = 'active' ORDER BY ends_on DESC LIMIT 1) m ON true
            LEFT JOIN membership_plans p ON p.id = m.plan_id
            LEFT JOIN LATERAL (SELECT trainer_id FROM trainer_client_assignments WHERE client_id = u.id AND ends_at IS NULL LIMIT 1) tca ON true
            LEFT JOIN users t ON t.id = tca.trainer_id
            LEFT JOIN LATERAL (SELECT routine_id, current_phase_id, phase_started_at FROM client_routine_assignments WHERE client_id = u.id AND ended_at IS NULL LIMIT 1) cra ON true
            LEFT JOIN routines r ON r.id = cra.routine_id
            LEFT JOIN routine_phases rp ON rp.id = cra.current_phase_id
            LEFT JOIN LATERAL (SELECT status, requested_at FROM account_deletion_requests
                WHERE user_id = u.id ORDER BY requested_at DESC LIMIT 1) deletion_request ON true
            WHERE u.id = %s""", (client['id'],)).fetchone()
        attendance = conn.execute("SELECT local_date FROM attendance WHERE client_id = %s AND local_date >= %s - 6 AND local_date <= %s ORDER BY local_date",
                                  (client['id'], row['today'], row['today'])).fetchall()
        phase_notice = conn.execute("""SELECT id, title, body, payload FROM notifications
            WHERE user_id = %s AND kind = 'new_phase_available' AND read_at IS NULL
            ORDER BY created_at DESC LIMIT 1""", (client['id'],)).fetchone()
    attendance_days = {d['local_date'].isoformat() for d in attendance}
    return {**row, 'today': row['today'].isoformat(),
            'profile_photo_data': (base64.b64encode(bytes(row['profile_photo'])).decode('ascii')
                                   if row['profile_photo'] else None),
            'profile_photo_mime': row['profile_photo_mime'],
            'membership_ends_on': row['membership_ends_on'].isoformat() if row['membership_ends_on'] else None,
            'phase_started_at': row['phase_started_at'].isoformat() if row['phase_started_at'] else None,
            'deletion_requested_at': row['deletion_requested_at'].isoformat() if row['deletion_requested_at'] else None,
            'attendance_7d_dates': sorted(attendance_days),
            'new_phase_notification': ({**phase_notice, 'id': str(phase_notice['id'])} if phase_notice else None)}


@app.patch('/api/v1/client/profile')
def update_client_profile(payload: ClientProfileUpdate,
                          client: dict = Depends(onboarded_client)) -> dict:
    fields = payload.model_fields_set
    if not (fields & {'first_name', 'last_name', 'email', 'phone', 'photo_data', 'photo_mime'}) \
            and not payload.remove_photo:
        raise _problem(422, 'EMPTY_PROFILE_UPDATE', 'Incluye al menos un cambio de perfil.')
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
            payload.photo_mime == 'image/png'
            and photo_bytes.startswith(b'\x89PNG\r\n\x1a\n')
        )
        if not valid_signature:
            raise _problem(415, 'INVALID_PROFILE_PHOTO', 'Usa una imagen JPG o PNG válida.')
    elif payload.photo_mime is not None:
        raise _problem(415, 'INVALID_PROFILE_PHOTO', 'Faltan los datos de la foto seleccionada.')

    first_name = (payload.first_name.strip() if payload.first_name is not None
                  else client['first_name'])
    last_name = (payload.last_name.strip() if payload.last_name is not None
                 else client['last_name'])
    email = str(payload.email).lower() if payload.email is not None else client['email']
    phone = client['phone']
    if 'phone' in fields:
        phone = payload.phone.strip() if payload.phone and payload.phone.strip() else None

    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""UPDATE users SET first_name = %s, last_name = %s,
                    email = %s, phone = %s, updated_at = now() WHERE id = %s""",
                    (first_name, last_name, email, phone, client['id']))
                if payload.remove_photo:
                    cur.execute("""UPDATE client_profiles SET profile_photo = NULL,
                        profile_photo_mime = NULL, updated_at = now() WHERE user_id = %s""",
                        (client['id'],))
                elif photo_bytes is not None:
                    cur.execute("""UPDATE client_profiles SET profile_photo = %s,
                        profile_photo_mime = %s, updated_at = now() WHERE user_id = %s""",
                        (photo_bytes, payload.photo_mime, client['id']))
                cur.execute("""INSERT INTO account_audit_events
                    (gym_id, actor_id, subject_id, event_type, details)
                    VALUES (%s, %s, %s, 'client_profile_updated', %s)""",
                    (client['gym_id'], client['id'], client['id'],
                     Jsonb({'email': email, 'photo_changed': photo_bytes is not None or payload.remove_photo})))
    except Exception as exc:
        constraint = getattr(getattr(exc, 'diag', None), 'constraint_name', '')
        if constraint == 'users_email_per_gym_uq':
            raise _problem(409, 'EMAIL_IN_USE', 'Ese correo ya está registrado en el gimnasio.')
        raise
    return client_dashboard(client)


@app.get('/api/v1/client/notifications')
def client_notifications(client: dict = Depends(onboarded_client)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT id, kind, title, body, payload, created_at
            FROM notifications WHERE user_id = %s AND kind = 'new_phase_available'
              AND read_at IS NULL ORDER BY created_at DESC LIMIT 10""",
            (client['id'],)).fetchall()
    return [{**row, 'id': str(row['id']), 'created_at': row['created_at'].isoformat()} for row in rows]


@app.post('/api/v1/client/notifications/{notification_id}/read', status_code=204)
def mark_client_notification_read(notification_id: uuid.UUID,
                                  client: dict = Depends(onboarded_client)) -> None:
    with pool.connection() as conn:
        conn.execute("UPDATE notifications SET read_at = now() WHERE id = %s AND user_id = %s AND read_at IS NULL",
                     (notification_id, client['id']))


@app.get('/api/v1/trainer/notifications')
def trainer_notifications(trainer: dict = Depends(active_trainer)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT id, kind, title, body, payload, created_at
            FROM notifications WHERE user_id = %s
              AND kind IN ('routine_phase_due', 'client_activity', 'daily_reminder')
              AND read_at IS NULL ORDER BY created_at DESC LIMIT 20""",
            (trainer['id'],)).fetchall()
    return [{**row, 'id': str(row['id']), 'created_at': row['created_at'].isoformat()} for row in rows]


@app.post('/api/v1/trainer/notifications/{notification_id}/read', status_code=204)
def mark_trainer_notification_read(notification_id: uuid.UUID,
                                  trainer: dict = Depends(active_trainer)) -> None:
    with pool.connection() as conn:
        conn.execute("UPDATE notifications SET read_at = now() WHERE id = %s AND user_id = %s AND read_at IS NULL",
                     (notification_id, trainer['id']))


@app.get('/api/v1/client/attendance')
def client_attendance(year: int = Query(ge=2000, le=2200), month: int = Query(ge=1, le=12),
                      client: dict = Depends(onboarded_client)) -> dict:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT local_date, checked_in_at, source FROM attendance
            WHERE client_id = %s AND extract(year FROM local_date) = %s AND extract(month FROM local_date) = %s
            ORDER BY local_date""", (client['id'], year, month)).fetchall()
    return {'days': [{'date': r['local_date'].isoformat(), 'checked_in_at': r['checked_in_at'].isoformat(), 'source': r['source']} for r in rows], 'total': len(rows)}


@app.get('/api/v1/client/routine')
def client_routine(day: int = Query(ge=1, le=7), client: dict = Depends(onboarded_client)) -> dict:
    with pool.connection() as conn:
        _advance_due_client_phase(conn, client['id'])
        assignment = conn.execute("""SELECT cra.id AS assignment_id, cra.current_phase_id, cra.phase_started_at,
                r.id AS routine_id, r.name AS routine_name, r.goal, r.days_per_week,
                rp.phase_number, rp.name AS phase_name, rp.status AS phase_status
            FROM client_routine_assignments cra JOIN routines r ON r.id = cra.routine_id
            JOIN routine_phases rp ON rp.id = cra.current_phase_id AND rp.status = 'published'
            WHERE cra.client_id = %s AND cra.ended_at IS NULL AND r.active LIMIT 1""",
            (client['id'],)).fetchone()
        if assignment is None:
            return {'assigned': False, 'exercises': []}
        exercises = conn.execute("""SELECT re.id, re.day_number, re.position, re.name, re.sets,
                re.reps, re.rest_seconds, COALESCE(re.instructions, ec.instructions) AS instructions,
                COALESCE(ec.media_url, re.media_url) AS media_url, ec.muscle_group, re.media_key
            FROM routine_exercises re
            LEFT JOIN exercise_catalog ec ON ec.id = re.exercise_catalog_id
            WHERE re.phase_id = %s AND re.day_number = %s ORDER BY re.position""",
            (assignment['current_phase_id'], day)).fetchall()
        today = conn.execute("SELECT (now() AT TIME ZONE timezone)::date AS d FROM gyms WHERE id = %s", (client['gym_id'],)).fetchone()['d']
        completed = conn.execute("SELECT id FROM workout_completions WHERE client_id = %s AND phase_id = %s AND workout_date = %s",
                                 (client['id'], assignment['current_phase_id'], today)).fetchone()
    return {'assigned': True, 'routine_id': str(assignment['routine_id']), 'routine_name': assignment['routine_name'],
            'goal': assignment['goal'], 'days_per_week': assignment['days_per_week'],
            'phase_id': str(assignment['current_phase_id']), 'phase_number': assignment['phase_number'],
            'phase_name': assignment['phase_name'], 'phase_status': assignment['phase_status'],
            'phase_started_at': assignment['phase_started_at'].isoformat(), 'completed_today': completed is not None,
            'exercises': [{**exercise, 'id': str(exercise['id'])} for exercise in exercises]}


@app.post('/api/v1/client/routine/complete', status_code=201)
def complete_client_workout(payload: WorkoutCompletionRequest,
                            client: dict = Depends(onboarded_client)) -> dict:
    with pool.connection() as conn:
        with conn.cursor() as cur:
            row = cur.execute("""SELECT cra.current_phase_id, (now() AT TIME ZONE g.timezone)::date AS today
                FROM client_routine_assignments cra JOIN users u ON u.id = cra.client_id
                JOIN gyms g ON g.id = u.gym_id JOIN routine_phases rp ON rp.id = cra.current_phase_id AND rp.status = 'published'
                WHERE cra.client_id = %s AND cra.ended_at IS NULL LIMIT 1 FOR UPDATE OF cra""",
                (client['id'],)).fetchone()
            if row is None:
                raise _problem(404, 'ROUTINE_NOT_ASSIGNED', 'Todavía no tienes una rutina asignada.')
            scheduled_count = cur.execute("SELECT count(*) AS total FROM routine_exercises WHERE phase_id = %s AND day_number = extract(isodow FROM %s)::integer",
                                          (row['current_phase_id'], row['today'])).fetchone()['total']
            if scheduled_count == 0:
                raise _problem(409, 'REST_DAY', 'Hoy no tienes ejercicios programados en tu rutina.')
            completion = cur.execute("""INSERT INTO workout_completions (client_id, phase_id, workout_date, duration_seconds)
                VALUES (%s, %s, %s, %s) ON CONFLICT (client_id, phase_id, workout_date) DO NOTHING RETURNING id""",
                (client['id'], row['current_phase_id'], row['today'], payload.duration_seconds)).fetchone()
            if completion is None:
                raise _problem(409, 'ALREADY_COMPLETED', 'La rutina de hoy ya se marcó como completada.')
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
                    (trainer['trainer_id'], f'{trainer["client_name"]} completó su rutina de hoy.',
                     Jsonb({'client_id': str(client['id']), 'routine_id': str(trainer['routine_id']) if trainer['routine_id'] else None,
                            'completion_id': str(completion['id'])})))
    return {'completed': True, 'date': row['today'].isoformat(),
            'exercise_count': scheduled_count, 'duration_seconds': payload.duration_seconds}


@app.post('/api/v1/client/account-deletion-request', status_code=201)
def request_account_deletion(client: dict = Depends(onboarded_client)) -> dict:
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
                recent = cur.execute("SELECT count(*) AS n FROM password_reset_codes WHERE user_id = %s AND created_at > now() - interval '1 hour'",
                                     (user['id'],)).fetchone()['n']
                if recent < 3:
                    cur.execute('INSERT INTO password_reset_codes (user_id, code_hash, expires_at) VALUES (%s, %s, now() + interval \'10 minutes\')',
                                (user['id'], _email_hash_code(code)))
                    should_deliver = True
    if should_deliver:
        try:
            _deliver_reset_code(email, code)
        except Exception:
            log.exception('Could not deliver password reset code')
            raise _problem(503, 'EMAIL_UNAVAILABLE', 'No se pudo enviar el correo. Intenta más tarde.')
    return {'message': 'Si el correo pertenece a una cuenta, recibirá un código de recuperación.'}


def _valid_reset_code(cur, email: str, code: str, *, consume: bool) -> bool:
    row = cur.execute(
        """SELECT c.id, c.user_id, c.code_hash, c.attempts
           FROM password_reset_codes c JOIN users u ON u.id = c.user_id
           WHERE u.email = %s AND c.consumed_at IS NULL AND c.expires_at > now()
             AND c.attempts < 5 ORDER BY c.created_at DESC LIMIT 1 FOR UPDATE OF c""",
        (email.lower(),)).fetchone()
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
    if not valid:
        raise _problem(400, 'INVALID_CODE', 'El código es incorrecto o ya venció.')
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
            (SELECT count(*) FROM routines WHERE gym_id = %s AND active) AS routines,
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
                concat_ws(' ', a.first_name, a.last_name) AS deactivated_by,
                p.name AS membership_plan, m.ends_on AS membership_ends_on, tp.specialty,
                (SELECT count(*) FROM trainer_client_assignments tca WHERE tca.trainer_id = u.id AND tca.ends_at IS NULL) AS assigned_clients
            FROM users u
            LEFT JOIN users a ON a.id = u.deactivated_by
            LEFT JOIN LATERAL (SELECT id, plan_id, ends_on FROM memberships
              WHERE client_id = u.id AND status = 'active' ORDER BY ends_on DESC LIMIT 1) m ON true
            LEFT JOIN membership_plans p ON p.id = m.plan_id
            LEFT JOIN trainer_profiles tp ON tp.user_id = u.id
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
            FROM routines r JOIN users u ON u.id = r.trainer_id
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


@app.get('/api/v1/admin/membership-plans')
def get_plans(admin: dict = Depends(active_admin)) -> list[dict]:
    with pool.connection() as conn:
        return conn.execute('SELECT id, name, price_mxn, duration_days, active FROM membership_plans WHERE gym_id = %s ORDER BY name',
                            (admin['gym_id'],)).fetchall()


class PlanUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    price_mxn: float | None = Field(default=None, ge=0)
    duration_days: int | None = Field(default=None, gt=0, le=3650)
    active: bool = True


@app.post('/api/v1/admin/membership-plans', status_code=201)
def create_plan(payload: PlanUpdate, admin: dict = Depends(active_admin)) -> dict:
    with pool.connection() as conn:
        try:
            row = conn.execute("""INSERT INTO membership_plans (gym_id, name, price_mxn, duration_days, active)
                VALUES (%s, %s, %s, %s, %s) RETURNING id, name, price_mxn, duration_days, active""",
                (admin['gym_id'], payload.name.strip(), payload.price_mxn, payload.duration_days, payload.active)).fetchone()
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
        row = conn.execute('UPDATE membership_plans SET name = %s, price_mxn = %s, duration_days = %s, active = %s WHERE id = %s AND gym_id = %s RETURNING id, name, price_mxn, duration_days, active',
                           (payload.name, payload.price_mxn, payload.duration_days, payload.active, plan_id, admin['gym_id'])).fetchone()
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
           tp.specialty FROM users u LEFT JOIN trainer_profiles tp ON tp.user_id = u.id
           WHERE u.gym_id = %s AND u.status = 'pending' AND u.role IN ('trainer', 'admin')
            ORDER BY u.created_at""", (admin['gym_id'],)).fetchall()


@app.get('/api/v1/admin/notifications')
def admin_notifications(admin: dict = Depends(active_admin)) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute("""SELECT id, kind, title, body, payload, created_at
            FROM notifications WHERE user_id = %s AND kind = 'staff_request'
              AND read_at IS NULL ORDER BY created_at DESC LIMIT 20""",
            (admin['id'],)).fetchall()
    return [{**row, 'id': str(row['id']), 'created_at': row['created_at'].isoformat()}
            for row in rows]


@app.post('/api/v1/admin/notifications/{notification_id}/read', status_code=204)
def mark_admin_notification_read(notification_id: uuid.UUID,
                                admin: dict = Depends(active_admin)) -> None:
    with pool.connection() as conn:
        conn.execute("""UPDATE notifications SET read_at = now()
            WHERE id = %s AND user_id = %s AND kind = 'staff_request'
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
                if user['status'] == 'deactivated':
                    raise _problem(409, 'ALREADY_DEACTIVATED', 'La cuenta ya está dada de baja.')
                cur.execute("""UPDATE users SET status = 'deactivated', status_reason = %s,
                   deactivation_reason = %s, deactivation_note = %s, deactivated_at = %s,
                   deactivated_by = %s WHERE id = %s""",
                   (payload.note or payload.reason, payload.reason, payload.note, now, admin['id'], user_id))
                cur.execute("""UPDATE auth_sessions SET revoked_at = coalesce(revoked_at, now()),
                    refresh_expires_at = (SELECT reactivation_until FROM users WHERE id = %s)
                    WHERE user_id = %s""", (user_id, user_id))
                cur.execute('INSERT INTO account_audit_events (gym_id, actor_id, subject_id, event_type, details) VALUES (%s, %s, %s, %s, %s)',
                            (admin['gym_id'], admin['id'], user_id, 'account_deactivated', {'reason': payload.reason, 'note': payload.note}))
                cur.execute('INSERT INTO notifications (user_id, kind, title, body, payload) VALUES (%s, %s, %s, %s, %s)',
                            (user_id, 'account_deactivated', 'Tu cuenta fue dada de baja', payload.note or payload.reason,
                             Jsonb({'deactivated_at': now.isoformat(), 'reactivation_until': (now + timedelta(days=90)).isoformat()})))
    except HTTPException:
        raise
    except Exception as exc:
        db_message = f'{exc} {getattr(getattr(exc, "diag", None), "message_primary", "")}'
        if 'único administrador' in db_message:
            raise _problem(409, 'LAST_ADMIN', 'No se puede dar de baja al único administrador activo.')
        if 'Reasigna los clientes' in db_message:
            raise _problem(409, 'TRAINER_HAS_CLIENTS', 'Reasigna los clientes antes de dar de baja al entrenador.')
        raise
    _deliver_notice_email(user['email'], 'Tu cuenta fue dada de baja · MUSKL',
        f"Tu cuenta fue dada de baja por el gimnasio.\nMotivo: {payload.reason}"
        f"\nReactivación disponible hasta: {(now + timedelta(days=90)).date().isoformat()}.")
    return {'id': str(user_id), 'status': 'deactivated', 'deactivated_at': now.isoformat(),
            'reactivation_until': (now + timedelta(days=90)).isoformat()}


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
            trainer = cur.execute("SELECT id FROM users WHERE id = %s AND gym_id = %s AND role = 'trainer' AND status = 'active' FOR UPDATE",
                                  (payload.new_trainer_id, admin['gym_id'])).fetchone()
            client = cur.execute("SELECT id FROM users WHERE id = %s AND gym_id = %s AND role = 'client' AND status = 'active' FOR UPDATE",
                                 (payload.client_id, admin['gym_id'])).fetchone()
            if trainer is None or client is None:
                raise _problem(404, 'ASSIGNMENT_TARGET_NOT_FOUND', 'El entrenador o socio no está activo.')
            cur.execute('UPDATE trainer_client_assignments SET ends_at = now() WHERE client_id = %s AND ends_at IS NULL',
                        (payload.client_id,))
            cur.execute('INSERT INTO trainer_client_assignments (trainer_id, client_id, assigned_by) VALUES (%s, %s, %s)',
                        (payload.new_trainer_id, payload.client_id, admin['id']))
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
