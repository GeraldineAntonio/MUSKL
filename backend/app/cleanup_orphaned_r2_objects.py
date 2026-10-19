"""Safely remove unreferenced profile photos and trainer certificates from private R2.

Run from backend. Default mode only previews. Add --execute to delete objects
that are not referenced by users.profile_photo_storage_key or
trainer_certifications.storage_key in Neon.
"""

from __future__ import annotations

import argparse
from getpass import getpass
from urllib.parse import urlparse

import boto3
import psycopg


KEEP_EMAIL = 'antonioeimy1@gmail.com'
MANAGED_PREFIXES = ('profile-photos/', 'certifications/')


def _object_key(storage_key: str | None) -> str | None:
    if not storage_key or not storage_key.startswith('r2://'):
        return None
    return storage_key.removeprefix('r2://')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true',
                        help='Delete the unreferenced objects after confirmation.')
    args = parser.parse_args()

    database_url = getpass('DATABASE_URL de Neon (entrada oculta): ').strip()
    parsed = urlparse(database_url)
    if parsed.scheme not in ('postgres', 'postgresql') or 'neon.tech' not in (parsed.hostname or ''):
        raise SystemExit('Se canceló: usa una URL PostgreSQL de Neon.')

    account_id = getpass('Cloudflare R2 Account ID (entrada oculta): ').strip()
    access_key = getpass('R2 Access Key ID (entrada oculta): ').strip()
    secret_key = getpass('R2 Secret Access Key (entrada oculta): ').strip()
    bucket = input('Nombre exacto del bucket PRIVADO de R2: ').strip()
    if not all((account_id, access_key, secret_key, bucket)):
        raise SystemExit('Se canceló: falta configuración de R2.')

    s3 = boto3.client(
        's3', endpoint_url=f'https://{account_id}.r2.cloudflarestorage.com',
        aws_access_key_id=access_key, aws_secret_access_key=secret_key,
        region_name='auto',
    )

    with psycopg.connect(database_url, connect_timeout=15) as conn:
        admin = conn.execute("""SELECT id FROM users
            WHERE lower(email) = %s AND role = 'admin' AND status = 'active'""",
            (KEEP_EMAIL,)).fetchone()
        if admin is None:
            raise SystemExit('Se canceló: no se encontró la cuenta admin activa que se debe conservar.')

        referenced: set[str] = set()
        for (value,) in conn.execute(
                'SELECT profile_photo_storage_key FROM users WHERE profile_photo_storage_key IS NOT NULL'):
            key = _object_key(value)
            if key:
                referenced.add(key)
        for (value,) in conn.execute(
                'SELECT storage_key FROM trainer_certifications WHERE storage_key IS NOT NULL'):
            key = _object_key(value)
            if key:
                referenced.add(key)

    candidates: list[str] = []
    retained = 0
    for prefix in MANAGED_PREFIXES:
        paginator = s3.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for item in page.get('Contents', []):
                key = item['Key']
                if key in referenced:
                    retained += 1
                else:
                    candidates.append(key)

    print(f'Cuenta protegida en Neon: {KEEP_EMAIL}')
    print(f'Bucket privado inspeccionado: {bucket}')
    print(f'Objetos vinculados a registros de Neon que se conservarían: {retained}')
    print(f'Objetos huérfanos candidatos a borrar: {len(candidates)}')
    for key in candidates:
        print(f'  {key}')

    if not args.execute or not candidates:
        print('\nVista previa solamente; no se borró nada.')
        if candidates:
            print('Para borrar únicamente esta lista, vuelve a ejecutar con --execute.')
        return

    confirmation = input(f'Escribe {KEEP_EMAIL} para borrar esos {len(candidates)} objetos: ').strip().lower()
    if confirmation != KEEP_EMAIL:
        raise SystemExit('Se canceló; no se borró nada.')

    deleted = 0
    for key in candidates:
        s3.delete_object(Bucket=bucket, Key=key)
        deleted += 1
    print(f'Borrados {deleted} objetos huérfanos. Ningún objeto con referencia en Neon fue borrado.')


if __name__ == '__main__':
    main()
