"""Remove only the MUSKL demo client, its seeded routine, and demo admin."""

from __future__ import annotations

import getpass

import psycopg
from psycopg.rows import dict_row


GYM_ID = '00000000-0000-4000-8000-000000000001'
DEMO_EMAIL = 'eimy.prueba@example.com'
DEMO_ADMIN_EMAIL = 'admin.muskl.demo@example.com'
ROUTINE_NAME = 'Rutina de prueba MUSKL · Cuerpo completo'


def main() -> None:
    database_url = getpass.getpass('Neon DATABASE_URL (no se mostrará): ').strip()
    if not database_url.startswith(('postgres://', 'postgresql://')):
        raise SystemExit('La URL debe ser una conexión PostgreSQL válida.')

    with psycopg.connect(database_url, connect_timeout=15, row_factory=dict_row) as conn:
        with conn.transaction():
            demo_client = conn.execute(
                """SELECT id, member_number FROM users WHERE gym_id = %s AND email = %s
                   AND role = 'client' FOR UPDATE""",
                (GYM_ID, DEMO_EMAIL),
            ).fetchone()
            demo_admin = conn.execute(
                """SELECT id FROM users WHERE gym_id = %s AND email = %s
                   AND role = 'admin' FOR UPDATE""",
                (GYM_ID, DEMO_ADMIN_EMAIL),
            ).fetchone()
            routine_rows = conn.execute(
                """SELECT DISTINCT r.id FROM routines r
                   JOIN account_audit_events e
                     ON e.event_type = 'demo_routine_assigned'
                    AND e.details->>'routine_id' = r.id::text
                   WHERE r.gym_id = %s AND r.name = %s""",
                (GYM_ID, ROUTINE_NAME),
            ).fetchall()
            routine_ids = [row['id'] for row in routine_rows]
            client_ids = [demo_client['id']] if demo_client else []

            if routine_ids or client_ids:
                conn.execute(
                    """DELETE FROM workout_completions
                       WHERE phase_id IN (
                         SELECT id FROM routine_phases WHERE routine_id = ANY(%s)
                       ) OR client_id = ANY(%s)""",
                    (routine_ids, client_ids),
                )
                conn.execute(
                    """DELETE FROM client_routine_assignments
                       WHERE routine_id = ANY(%s) OR client_id = ANY(%s)""",
                    (routine_ids, client_ids),
                )
                conn.execute(
                    """DELETE FROM routines WHERE id = ANY(%s)""",
                    (routine_ids,),
                )
                conn.execute(
                    """DELETE FROM account_audit_events
                       WHERE event_type = 'demo_routine_assigned'
                         AND (details->>'routine_id' = ANY(%s) OR subject_id = ANY(%s))""",
                    ([str(routine_id) for routine_id in routine_ids], client_ids),
                )
            if demo_client:
                conn.execute(
                    'DELETE FROM client_groups WHERE gym_id = %s AND member_number = %s',
                    (GYM_ID, demo_client['member_number']),
                )
                conn.execute('DELETE FROM users WHERE id = %s', (demo_client['id'],))

            admin_removed = False
            if demo_admin:
                admin_id = demo_admin['id']
                has_other_routines = conn.execute(
                    'SELECT 1 FROM routines WHERE trainer_id = %s LIMIT 1',
                    (admin_id,),
                ).fetchone()
                if not has_other_routines:
                    conn.execute(
                        'DELETE FROM admin_invite_tokens WHERE created_by = %s',
                        (admin_id,),
                    )
                    conn.execute('DELETE FROM users WHERE id = %s', (admin_id,))
                    admin_removed = True

    print(
        f"Limpieza completa: cliente {'eliminado' if demo_client else 'no encontrado'}, "
        f"rutinas demo eliminadas: {len(routine_ids)}, "
        f"administrador demo {'eliminado' if admin_removed else 'no encontrado o conservado'}."
    )
    if demo_admin and not admin_removed:
        print('El administrador demo se conservó porque tiene otras rutinas asociadas.')


if __name__ == '__main__':
    main()
