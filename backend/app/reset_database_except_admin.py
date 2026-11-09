"""Reset MUSKL application data in Neon while keeping one admin account.

Preview with:
    python -m app.reset_database_except_admin

Delete with:
    python -m app.reset_database_except_admin --execute

The reset empties public application tables, removes every other user, and
keeps the selected admin plus the one gym row required by its foreign key.
Schema objects and migration history remain intact.
"""

from __future__ import annotations

import argparse
from getpass import getpass
from urllib.parse import urlparse

import psycopg
from psycopg import sql
from psycopg.rows import dict_row


EXCLUDED_TABLES = {'users', 'gyms', 'muskl_schema_migrations'}


def app_tables(conn: psycopg.Connection) -> list[str]:
    """Return public base tables, excluding retained and extension tables."""
    rows = conn.execute(
        """SELECT c.relname
           FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relkind = 'r'
             AND c.relname <> ALL(%s)
             AND NOT EXISTS (
               SELECT 1
               FROM pg_depend d
               WHERE d.classid = 'pg_class'::regclass
                 AND d.objid = c.oid
                 AND d.deptype = 'e'
             )
           ORDER BY c.relname""",
        (list(EXCLUDED_TABLES),),
    ).fetchall()
    return [row['relname'] for row in rows]


def row_counts(conn: psycopg.Connection, tables: list[str]) -> dict[str, int]:
    counts = {}
    for table in tables:
        count = conn.execute(
            sql.SQL('SELECT count(*) AS total FROM {}').format(
                sql.Identifier('public', table)
            )
        ).fetchone()['total']
        if count:
            counts[table] = count
    return counts


def print_preview(
    conn: psycopg.Connection, tables: list[str], keep_email: str
) -> None:
    preserved = conn.execute(
        """SELECT role::text AS role, status::text AS status
           FROM users WHERE lower(email) = %s""",
        (keep_email,),
    ).fetchall()
    if (
        len(preserved) != 1
        or preserved[0]['role'] != 'admin'
        or preserved[0]['status'] != 'active'
    ):
        raise SystemExit(
            f'Se canceló: debe existir exactamente una cuenta admin activa {keep_email}.'
        )

    users = conn.execute(
        """SELECT role::text AS role, status::text AS status, count(*) AS total
           FROM users WHERE lower(email) <> %s GROUP BY role, status
           ORDER BY role, status""",
        (keep_email,),
    ).fetchall()
    print(f'Cuenta que se conservará: {keep_email} (admin activo)')
    print('Otras cuentas que se borrarán:')
    if users:
        for row in users:
            print(f"  {row['role']} / {row['status']}: {row['total']}")
    else:
        print('  Ninguna.')

    counts = row_counts(conn, tables)
    print('Registros que se borrarán de las tablas de la app:')
    if counts:
        for table, count in counts.items():
            print(f'  {table}: {count}')
    else:
        print('  Ninguno.')
    print(
        'Se conservarán el esquema, las migraciones, la cuenta indicada y su gimnasio asociado.'
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--execute', action='store_true', help='Borra los datos tras pedir confirmación.'
    )
    args = parser.parse_args()

    keep_email = input('Correo de la cuenta admin que se conservará: ').strip().lower()
    if not keep_email or '@' not in keep_email:
        raise SystemExit('Se canceló: escribe un correo válido para el admin.')

    database_url = getpass('Neon DATABASE_URL (no se mostrará): ').strip()
    parsed = urlparse(database_url)
    if (
        parsed.scheme not in ('postgres', 'postgresql')
        or 'neon.tech' not in (parsed.hostname or '').lower()
    ):
        raise SystemExit('Se canceló: usa una URL PostgreSQL de Neon.')

    with psycopg.connect(database_url, connect_timeout=15, row_factory=dict_row) as conn:
        if not args.execute:
            tables = app_tables(conn)
            print_preview(conn, tables, keep_email)
            print('\nVista previa únicamente; no se borró nada.')
            print('Vuelve a ejecutar con --execute para realizar el borrado.')
            return

        with conn.transaction():
            admin = conn.execute(
                """SELECT id, gym_id FROM users
                   WHERE lower(email) = %s AND role = 'admin' AND status = 'active'
                   FOR UPDATE""",
                (keep_email,),
            ).fetchall()
            if len(admin) != 1:
                raise SystemExit(
                    f'Se canceló: debe existir exactamente una cuenta admin activa {keep_email}.'
                )
            tables = app_tables(conn)
            locked_tables = ['users', 'gyms', *tables]
            if locked_tables:
                lock_tables = sql.SQL(', ').join(
                    sql.Identifier('public', table) for table in locked_tables
                )
                conn.execute(
                    sql.SQL('LOCK TABLE {} IN ACCESS EXCLUSIVE MODE').format(
                        lock_tables
                    )
                )
            print_preview(conn, tables, keep_email)
            confirmation = input(
                f'\nEscribe BORRAR TODO EXCEPTO {keep_email} para confirmar: '
            ).strip()
            if confirmation != f'BORRAR TODO EXCEPTO {keep_email}':
                raise SystemExit('Se canceló; no se borró nada.')

            if tables:
                table_list = sql.SQL(', ').join(
                    sql.Identifier('public', table) for table in tables
                )
                conn.execute(
                    sql.SQL('TRUNCATE TABLE {} RESTART IDENTITY').format(
                        table_list
                    )
                )
            keep_id, keep_gym_id = admin[0]['id'], admin[0]['gym_id']
            conn.execute(
                'UPDATE users SET deactivated_by = NULL, rejected_by = NULL'
            )
            conn.execute('DELETE FROM users WHERE id <> %s', (keep_id,))
            conn.execute('DELETE FROM gyms WHERE id <> %s', (keep_gym_id,))
            conn.execute(
                """UPDATE gyms SET name = 'MUSKL Gym', phone = NULL, address = NULL,
                          opening_hours = '{}'::jsonb,
                          timezone = 'America/Mexico_City', updated_at = now()
                   WHERE id = %s""",
                (keep_gym_id,),
            )
            sequence = conn.execute(
                "SELECT to_regclass('public.member_number_seq') AS sequence"
            ).fetchone()['sequence']
            if sequence is not None:
                conn.execute('ALTER SEQUENCE public.member_number_seq RESTART WITH 1001')

    print('Limpieza completada. Se conservó únicamente la cuenta admin indicada y su gimnasio base.')
    print('Los archivos almacenados externamente en R2 no se borraron.')


if __name__ == '__main__':
    main()
