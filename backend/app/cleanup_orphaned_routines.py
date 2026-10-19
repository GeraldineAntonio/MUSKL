"""Preview and remove unused active routines left without their trainer.

Run from backend with a Neon DATABASE_URL. By default the script only previews.
It removes routines only when they have no client assignments and no workout
history, so deleting them cannot erase a client's training record.
"""

from __future__ import annotations

import argparse
from getpass import getpass
from urllib.parse import urlparse

import psycopg
from psycopg.rows import dict_row


ADMIN_EMAIL = 'antonioeimy1@gmail.com'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true',
                        help='Delete the previewed unused orphan routines.')
    args = parser.parse_args()

    database_url = getpass('DATABASE_URL de Neon (entrada oculta): ').strip()
    parsed = urlparse(database_url)
    if parsed.scheme not in ('postgres', 'postgresql') or 'neon.tech' not in (parsed.hostname or ''):
        raise SystemExit('Se canceló: usa una URL PostgreSQL de Neon.')

    with psycopg.connect(database_url, connect_timeout=15,
                         row_factory=dict_row) as conn:
        admin = conn.execute("""SELECT id, gym_id FROM users
            WHERE lower(email) = %s AND role = 'admin' AND status = 'active'""",
            (ADMIN_EMAIL,)).fetchone()
        if admin is None:
            raise SystemExit('Se canceló: no se encontró el administrador protegido.')

        routines = conn.execute("""SELECT r.id, r.name, r.goal, r.created_at,
                (SELECT count(*) FROM client_routine_assignments a
                    WHERE a.routine_id = r.id) AS assignments,
                (SELECT count(*) FROM workout_completions wc
                    JOIN routine_phases rp ON rp.id = wc.phase_id
                    WHERE rp.routine_id = r.id) AS workout_records
            FROM routines r
            WHERE r.gym_id = %s AND r.active AND r.trainer_id IS NULL
            ORDER BY r.created_at, r.name""", (admin['gym_id'],)).fetchall()

        print(f'Administrador protegido: {ADMIN_EMAIL}')
        print('Rutinas activas sin entrenador:')
        if not routines:
            print('  Ninguna.')
            return

        blocked = False
        for routine in routines:
            print(f"  {routine['name']} | {routine['goal']} | id={routine['id']} | "
                  f"asignaciones={routine['assignments']} | "
                  f"sesiones_guardadas={routine['workout_records']}")
            blocked |= bool(routine['assignments'] or routine['workout_records'])

        if blocked:
            print('\nNo se borró nada: al menos una rutina tiene asignaciones o historial de entrenamiento.')
            return
        if not args.execute:
            print('\nVista previa solamente; no se borró nada.')
            print('Para borrar únicamente estas rutinas, vuelve a ejecutar con --execute.')
            return

        confirmation = input(f'Escribe {ADMIN_EMAIL} para borrar estas {len(routines)} rutinas: ').strip().lower()
        if confirmation != ADMIN_EMAIL:
            raise SystemExit('Se canceló; no se borró nada.')

        routine_ids = [row['id'] for row in routines]
        with conn.transaction():
            locked = conn.execute("""SELECT id FROM routines
                WHERE id = ANY(%s) AND gym_id = %s AND active AND trainer_id IS NULL
                FOR UPDATE""", (routine_ids, admin['gym_id'])).fetchall()
            locked_ids = [row['id'] for row in locked]
            remaining = conn.execute("""SELECT
                    EXISTS (SELECT 1 FROM client_routine_assignments
                        WHERE routine_id = ANY(%s)) AS has_assignments,
                    EXISTS (SELECT 1 FROM workout_completions wc
                        JOIN routine_phases rp ON rp.id = wc.phase_id
                        WHERE rp.routine_id = ANY(%s)) AS has_workouts""",
                (locked_ids, locked_ids)).fetchone()
            if remaining['has_assignments'] or remaining['has_workouts']:
                raise SystemExit('Se canceló: apareció una asignación o sesión guardada; no se borró nada.')
            deleted = conn.execute("""DELETE FROM routines
                WHERE id = ANY(%s) AND gym_id = %s AND active AND trainer_id IS NULL
                RETURNING id""", (locked_ids, admin['gym_id'])).fetchall()
        print(f'Borradas {len(deleted)} rutinas huérfanas sin asignaciones ni historial.')


if __name__ == '__main__':
    main()
