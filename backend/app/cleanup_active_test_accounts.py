"""Permanently remove every account except the primary admin.

Run from backend with DATABASE_URL set. The script previews first; pass
--execute and type the protected email to permanently remove the accounts,
including accounts already marked deactivated.
"""

from __future__ import annotations

import argparse
from collections import Counter
from getpass import getpass
from urllib.parse import urlparse

import psycopg
from psycopg.types.json import Jsonb


KEEP_EMAIL = 'antonioeimy1@gmail.com'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true',
                        help='Permanently delete the matching accounts.')
    args = parser.parse_args()

    database_url = getpass('DATABASE_URL de Neon (entrada oculta): ').strip()
    parsed = urlparse(database_url)
    if parsed.scheme not in ('postgres', 'postgresql') or 'neon.tech' not in (parsed.hostname or ''):
        raise SystemExit('Se canceló: usa una URL PostgreSQL de Neon.')

    with psycopg.connect(database_url, connect_timeout=15) as conn:
        migrations = {row[0] for row in conn.execute(
            'SELECT version FROM muskl_schema_migrations').fetchall()}
        if not {'004', '016'}.issubset(migrations):
            raise SystemExit('Se canceló: faltan migraciones de borrado seguro 004 y 016.')

        primary = conn.execute("""SELECT id, gym_id FROM users
            WHERE lower(email) = %s AND role = 'admin' AND status = 'active'""",
            (KEEP_EMAIL,)).fetchone()
        if primary is None:
            raise SystemExit('Se canceló: no se encontró activa la cuenta admin que se debe conservar.')

        rows = conn.execute("""SELECT id, role, status, member_number FROM users
            WHERE lower(email) <> %s ORDER BY role, status""", (KEEP_EMAIL,)).fetchall()
        counts = Counter((row[1], row[2]) for row in rows)
        print(f'Cuenta protegida: {KEEP_EMAIL}')
        print('Cuentas que se borrarían:' if not args.execute else 'Cuentas encontradas para borrar:')
        if not counts:
            print('  Ninguna.')
            return
        for (role, status), count in sorted(counts.items()):
            print(f'  {role} / {status}: {count}')
        if not args.execute:
            print('\nVista previa solamente; no se borró nada.')
            print('Para ejecutar: añade --execute al comando.')
            return

        confirmation = input(f'Escribe {KEEP_EMAIL} para confirmar el borrado permanente: ').strip().lower()
        if confirmation != KEEP_EMAIL:
            raise SystemExit('Se canceló; no se borró nada.')

        ids = [row[0] for row in rows]
        member_numbers = [row[3] for row in rows if row[3]]
        with conn.transaction():
            id_text = [str(user_id) for user_id in ids]
            conn.execute("""UPDATE account_audit_events SET details = '{}'::jsonb
                WHERE actor_id = ANY(%s) OR subject_id = ANY(%s)
                   OR details->>'client_id' = ANY(%s)
                   OR details->>'trainer_id' = ANY(%s)""",
                (ids, ids, id_text, id_text))
            conn.execute('UPDATE account_deletion_requests SET note = NULL WHERE user_id = ANY(%s)',
                         (ids,))
            conn.execute("""DELETE FROM notifications
                WHERE payload->>'client_id' = ANY(%s)
                   OR payload->>'trainer_id' = ANY(%s)
                   OR payload->>'user_id' = ANY(%s)""",
                (id_text, id_text, id_text))
            conn.execute('DELETE FROM admin_invite_tokens WHERE created_by = ANY(%s)', (ids,))
            deleted = conn.execute('DELETE FROM users WHERE id = ANY(%s) RETURNING gym_id',
                                   (ids,)).fetchall()
            if member_numbers:
                conn.execute("""DELETE FROM client_groups g
                    WHERE g.member_number = ANY(%s)
                      AND NOT EXISTS (SELECT 1 FROM client_group_members gm WHERE gm.group_id = g.id)""",
                    (member_numbers,))
            gym_counts = Counter(row[0] for row in deleted)
            for gym_id, count in gym_counts.items():
                conn.execute("""INSERT INTO account_audit_events (gym_id, event_type, details)
                    VALUES (%s, 'account_data_purged', %s)""",
                    (gym_id, Jsonb({'accounts': count})))
        print(f'Borrado permanente completado: {len(deleted)} cuenta(s).')
        print('La cuenta principal se conservó. Los archivos R2 podrían requerir limpieza aparte.')


if __name__ == '__main__':
    main()
