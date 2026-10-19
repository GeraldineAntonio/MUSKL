"""Preview or remove client test accounts and their linked database records.

Run from backend with DATABASE_URL set to the Neon database. Trainers, admins,
routine definitions, gym settings, and unlinked preloaded member registry rows
are preserved. A normal run is a dry run; pass --execute to delete clients.
"""

from __future__ import annotations

import argparse
import os
from collections import Counter
from getpass import getpass

import psycopg
from psycopg.rows import dict_row


KEEP_EMAIL = 'antonioeimy1@gmail.com'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true',
                        help='Permanently remove all client accounts in the primary admin gym.')
    args = parser.parse_args()

    database_url = os.environ.get('DATABASE_URL', '').strip()
    if not database_url:
        database_url = getpass('DATABASE_URL de Neon (entrada oculta): ').strip()
    if not database_url.startswith(('postgres://', 'postgresql://')) or 'neon.tech' not in database_url:
        raise SystemExit('Se canceló: carga DATABASE_URL de Neon en el entorno.')

    with psycopg.connect(database_url, connect_timeout=15, row_factory=dict_row) as conn:
        admin = conn.execute("""SELECT id, gym_id FROM users
            WHERE lower(email) = %s AND role = 'admin' AND status = 'active'""",
            (KEEP_EMAIL,)).fetchone()
        if admin is None:
            raise SystemExit(f'Se canceló: no se encontró el admin protegido {KEEP_EMAIL}.')

        clients = conn.execute("""SELECT id, status, member_number FROM users
            WHERE gym_id = %s AND role = 'client' ORDER BY created_at""",
            (admin['gym_id'],)).fetchall()
        ids = [row['id'] for row in clients]
        statuses = Counter(row['status'] for row in clients)
        registry_ids = []
        group_numbers = [row['member_number'] for row in clients if row['member_number']]
        if ids:
            registry_ids = [row['id'] for row in conn.execute("""SELECT DISTINCT member_registry_id AS id
                FROM client_profiles WHERE user_id = ANY(%s) AND member_registry_id IS NOT NULL""",
                (ids,)).fetchall()]

        print(f'Cuenta protegida: {KEEP_EMAIL}')
        print(f'Clientes encontrados: {len(clients)}')
        for status, count in sorted(statuses.items()):
            print(f'  {status}: {count}')
        print(f'Fichas de socios vinculadas: {len(registry_ids)}')
        if not ids:
            print('No hay cuentas cliente para borrar.')
            return
        if not args.execute:
            print('\nVista previa solamente; no se borró nada.')
            print('Para borrar solo estas cuentas cliente: añade --execute al comando.')
            return

        confirmation = input('Escribe BORRAR CLIENTES para confirmar el borrado: ').strip()
        if confirmation != 'BORRAR CLIENTES':
            raise SystemExit('Se canceló; no se borró nada.')

        with conn.transaction():
            locked = conn.execute("""SELECT id FROM users
                WHERE id = ANY(%s) AND gym_id = %s AND role = 'client' FOR UPDATE""",
                (ids, admin['gym_id'])).fetchall()
            locked_ids = [row['id'] for row in locked]
            if len(locked_ids) != len(ids):
                raise SystemExit('Se canceló: cambió la lista de clientes; no se borró nada.')

            text_ids = [str(user_id) for user_id in locked_ids]
            conn.execute("""UPDATE account_audit_events SET details = '{}'::jsonb
                WHERE actor_id = ANY(%s) OR subject_id = ANY(%s)
                   OR details->>'client_id' = ANY(%s)""",
                (locked_ids, locked_ids, text_ids))
            conn.execute("""DELETE FROM notifications
                WHERE user_id = ANY(%s) OR payload->>'client_id' = ANY(%s)""",
                (locked_ids, text_ids))
            conn.execute('DELETE FROM users WHERE id = ANY(%s)', (locked_ids,))

            if registry_ids:
                conn.execute('DELETE FROM client_member_registry WHERE id = ANY(%s)',
                             (registry_ids,))
            if group_numbers:
                conn.execute("""DELETE FROM client_groups g
                    WHERE g.gym_id = %s AND g.member_number = ANY(%s)
                      AND NOT EXISTS (SELECT 1 FROM client_group_members gm WHERE gm.group_id = g.id)""",
                    (admin['gym_id'], group_numbers))

        print(f'Borrados {len(locked_ids)} clientes y sus datos vinculados.')
        print('Se conservaron el admin, entrenadores, rutinas, configuración del gimnasio y fichas pre-cargadas sin cuenta.')
        print('Las fotos de perfil borradas pueden dejar objetos huérfanos en R2; limpia esos objetos con cleanup_orphaned_r2_objects.')


if __name__ == '__main__':
    main()
