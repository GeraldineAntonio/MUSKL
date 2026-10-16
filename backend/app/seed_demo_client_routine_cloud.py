"""Create and assign one demo routine in the Neon database."""

from __future__ import annotations

import getpass
import secrets
import uuid
from datetime import timedelta

import psycopg
from argon2 import PasswordHasher
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


ROUTINE_NAME = 'Rutina de prueba MUSKL · Cuerpo completo'
DEMO_EMAIL = 'eimy.prueba@example.com'
DEMO_ADMIN_EMAIL = 'admin.muskl.demo@example.com'
GYM_ID = '00000000-0000-4000-8000-000000000001'
DEMO_PASSWORD_HASHER = PasswordHasher()
WORKOUT_DAYS = (1, 3, 5)
EXERCISES = (
    ('Sentadilla goblet', 4, '10', 90),
    ('Press de banca con barra', 4, '8-12', 90),
    ('Jalón al pecho', 4, '10-12', 75),
    ('Peso muerto rumano', 3, '10', 90),
    ('Press de hombro con mancuernas', 3, '10', 75),
    ('Plancha', 3, '30-45 segundos', 60),
)


def _insert_exercises(conn: psycopg.Connection, phase_id: uuid.UUID) -> None:
    has_catalog = conn.execute(
        "SELECT to_regclass('public.exercise_catalog') IS NOT NULL AS available"
    ).fetchone()['available']
    for day in WORKOUT_DAYS:
        for position, (name, sets, reps, rest_seconds) in enumerate(EXERCISES, 1):
            catalog = None
            if has_catalog:
                catalog = conn.execute(
                    """SELECT id, media_url, instructions FROM exercise_catalog
                       WHERE name = %s AND active""",
                    (name,),
                ).fetchone()
            if catalog:
                conn.execute(
                    """INSERT INTO routine_exercises
                       (phase_id, day_number, position, exercise_catalog_id, name,
                        sets, reps, rest_seconds, media_url, instructions)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                    (phase_id, day, position, catalog['id'], name, sets, reps,
                     rest_seconds, catalog['media_url'], catalog['instructions']),
                )
            else:
                conn.execute(
                    """INSERT INTO routine_exercises
                       (phase_id, day_number, position, name, sets, reps, rest_seconds)
                       VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                    (phase_id, day, position, name, sets, reps, rest_seconds),
                )


def main() -> None:
    database_url = getpass.getpass('Neon DATABASE_URL (no se mostrará): ').strip()
    if not database_url.startswith(('postgres://', 'postgresql://')):
        raise SystemExit('La URL debe ser una conexión PostgreSQL válida.')
    demo_password = f'MUSKL-{secrets.token_urlsafe(15)}'
    demo_admin_password = None

    with psycopg.connect(database_url, connect_timeout=15, row_factory=dict_row) as conn:
        with conn.transaction():
            if conn.execute(
                'SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                (GYM_ID, DEMO_EMAIL),
            ).fetchone():
                raise SystemExit(
                    f'Ya existe {DEMO_EMAIL}; no cambié sus datos ni su contraseña.'
                )

            plan = conn.execute(
                """SELECT id, duration_days FROM membership_plans
                   WHERE gym_id = %s AND active AND duration_days IS NOT NULL
                     AND min_group_size <= 1 AND max_group_size >= 1
                   ORDER BY (name = 'Normal') DESC, created_at LIMIT 1""",
                (GYM_ID,),
            ).fetchone()
            if plan is None:
                raise SystemExit('No hay un plan individual activo con duración configurada.')

            trainer = conn.execute(
                """SELECT id, role FROM users WHERE gym_id = %s AND status = 'active'
                   AND role IN ('trainer', 'admin')
                   ORDER BY (role = 'trainer') DESC, created_at LIMIT 1""",
                (GYM_ID,),
            ).fetchone()
            if trainer is None:
                if conn.execute(
                    'SELECT 1 FROM users WHERE gym_id = %s AND email = %s',
                    (GYM_ID, DEMO_ADMIN_EMAIL),
                ).fetchone():
                    raise SystemExit(
                        f'Ya existe {DEMO_ADMIN_EMAIL}, pero no está activo; no lo modifiqué.'
                    )
                demo_admin_password = f'MUSKL-{secrets.token_urlsafe(15)}'
                trainer = conn.execute(
                    """INSERT INTO users
                       (gym_id, role, status, first_name, last_name, email, password_hash)
                       VALUES (%s, 'admin', 'active', 'MUSKL', 'Demo', %s, %s)
                       RETURNING id, role""",
                    (GYM_ID, DEMO_ADMIN_EMAIL,
                     DEMO_PASSWORD_HASHER.hash(demo_admin_password)),
                ).fetchone()

            member_seq = conn.execute(
                "SELECT nextval('member_number_seq') AS value"
            ).fetchone()['value']
            member_number = f'MSK-{member_seq:06d}'
            client = conn.execute(
                """INSERT INTO users
                   (gym_id, role, status, first_name, last_name, email, member_number, password_hash)
                   VALUES (%s, 'client', 'active', 'Eimy', 'Prueba', %s, %s, %s)
                   RETURNING id, gym_id, first_name, last_name, member_number""",
                (GYM_ID, DEMO_EMAIL, member_number, DEMO_PASSWORD_HASHER.hash(demo_password)),
            ).fetchone()
            conn.execute(
                """INSERT INTO client_profiles
                   (user_id, goal, experience_level, days_per_week, onboarding_completed_at)
                   VALUES (%s, 'Masa muscular', 'principiante', 3, now())""",
                (client['id'],),
            )
            group = conn.execute(
                """INSERT INTO client_groups (gym_id, member_number, plan_id)
                   VALUES (%s, %s, %s) RETURNING id""",
                (GYM_ID, member_number, plan['id']),
            ).fetchone()
            conn.execute(
                """INSERT INTO client_group_members (group_id, user_id, is_primary)
                   VALUES (%s, %s, true)""",
                (group['id'], client['id']),
            )
            starts = conn.execute(
                'SELECT (now() AT TIME ZONE timezone)::date AS date FROM gyms WHERE id = %s',
                (GYM_ID,),
            ).fetchone()['date']
            conn.execute(
                """INSERT INTO memberships
                   (client_id, plan_id, starts_on, ends_on, registered_by)
                   VALUES (%s, %s, %s, %s, %s)""",
                (client['id'], plan['id'], starts,
                 starts + timedelta(days=plan['duration_days'] - 1), client['id']),
            )
            if trainer['role'] == 'trainer':
                conn.execute(
                    """INSERT INTO trainer_client_assignments (trainer_id, client_id, assigned_by)
                       VALUES (%s, %s, %s)""",
                    (trainer['id'], client['id'], trainer['id']),
                )

            routine = conn.execute(
                """SELECT id FROM routines
                   WHERE gym_id = %s AND trainer_id = %s AND name = %s AND active
                   ORDER BY created_at DESC LIMIT 1""",
                (client['gym_id'], trainer['id'], ROUTINE_NAME),
            ).fetchone()
            if routine is None:
                routine = conn.execute(
                    """INSERT INTO routines (gym_id, trainer_id, name, goal, days_per_week)
                       VALUES (%s, %s, %s, 'Masa muscular', 3) RETURNING id""",
                    (client['gym_id'], trainer['id'], ROUTINE_NAME),
                ).fetchone()

            phase = conn.execute(
                """SELECT id FROM routine_phases
                   WHERE routine_id = %s AND phase_number = 1""",
                (routine['id'],),
            ).fetchone()
            if phase is None:
                phase = conn.execute(
                    """INSERT INTO routine_phases
                       (routine_id, phase_number, name, duration_weeks, status, published_at)
                       VALUES (%s, 1, 'Fase 1 · Fuerza base', 8, 'published', now())
                       RETURNING id""",
                    (routine['id'],),
                ).fetchone()
            exercise_count = conn.execute(
                'SELECT count(*) AS total FROM routine_exercises WHERE phase_id = %s',
                (phase['id'],),
            ).fetchone()['total']
            if exercise_count == 0:
                _insert_exercises(conn, phase['id'])
            conn.execute(
                """UPDATE routine_phases SET status = 'published',
                   published_at = COALESCE(published_at, now()) WHERE id = %s""",
                (phase['id'],),
            )

            current = conn.execute(
                """SELECT cra.id, cra.routine_id, r.name
                   FROM client_routine_assignments cra
                   JOIN routines r ON r.id = cra.routine_id
                   WHERE cra.client_id = %s AND cra.ended_at IS NULL
                   FOR UPDATE OF cra""",
                (client['id'],),
            ).fetchone()
            conn.execute(
                """INSERT INTO client_routine_assignments
                   (client_id, routine_id, current_phase_id, assigned_by)
                   VALUES (%s, %s, %s, %s)""",
                (client['id'], routine['id'], phase['id'], trainer['id']),
            )
            conn.execute(
                """INSERT INTO account_audit_events
                   (gym_id, actor_id, subject_id, event_type, details)
                   VALUES (%s, %s, %s, 'demo_routine_assigned', %s)""",
                (client['gym_id'], trainer['id'], client['id'],
                 Jsonb({'routine_id': str(routine['id'])})),
            )

    print(
        f"Cuenta cliente y rutina listas para {client['first_name']} {client['last_name']}.\n"
        f"Correo: {DEMO_EMAIL}\nContraseña temporal: {demo_password}\n"
        f"Número de socio: {client['member_number']}\nAbre Mi rutina en la app cliente."
    )
    if demo_admin_password is not None:
        print(
            '\nTambién se creó el administrador responsable de la rutina de prueba:\n'
            f'Correo: {DEMO_ADMIN_EMAIL}\nContraseña temporal: {demo_admin_password}'
        )


if __name__ == '__main__':
    main()
