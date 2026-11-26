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
    notification_push = asyncio.create_task(_notification_push_loop())
    yield
    cleanup.cancel()
    phase_maintenance.cancel()
    notification_push.cancel()
    with suppress(asyncio.CancelledError):
        await cleanup
    with suppress(asyncio.CancelledError):
        await phase_maintenance
    with suppress(asyncio.CancelledError):
        await notification_push
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


async def _notification_push_loop() -> None:
    """Deliver opted-in in-app notifications as device push notifications."""
    while True:
        try:
            await asyncio.to_thread(_deliver_pending_notification_pushes)
        except Exception:
            log.exception('Notification push delivery failed; it will retry')
        await asyncio.sleep(30)


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


class PushNotificationPreference(BaseModel):
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
       