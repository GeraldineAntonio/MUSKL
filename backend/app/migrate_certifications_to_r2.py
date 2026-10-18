"""Move existing local trainer certifications to the configured private R2 bucket."""

from __future__ import annotations

import os
import uuid
from pathlib import Path

import psycopg
from psycopg.rows import dict_row

from app.object_storage import configured, put_certificate


DATABASE_URL = os.environ['DATABASE_URL']
UPLOAD_DIR = Path(os.getenv('MUSKL_UPLOAD_DIR', '/app/uploads')).resolve()
MIME_TYPES = {
    '.pdf': ('application/pdf', b'%PDF-'),
    '.png': ('image/png', b'\x89PNG\r\n\x1a\n'),
    '.jpg': ('image/jpeg', b'\xff\xd8\xff'),
    '.jpeg': ('image/jpeg', b'\xff\xd8\xff'),
}


def main() -> None:
    if not configured():
        raise SystemExit('Configura credenciales y el bucket privado de R2 primero.')

    moved = 0
    missing: list[str] = []
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        rows = conn.execute("""SELECT id, trainer_id, title, storage_key
            FROM trainer_certifications ORDER BY created_at""").fetchall()
        for row in rows:
            if row['storage_key'].startswith('r2://'):
                continue
            relative_key = row['storage_key'].removeprefix('local://')
            source = (UPLOAD_DIR / relative_key).resolve()
            if not source.is_relative_to(UPLOAD_DIR) or not source.is_file():
                missing.append(str(row['id']))
                continue
            if source.stat().st_size > 10 * 1024 * 1024:
                missing.append(str(row['id']))
                continue
            ext = source.suffix.lower()
            format_info = MIME_TYPES.get(ext)
            if format_info is None:
                missing.append(str(row['id']))
                continue
            mime_type, signature = format_info
            data = source.read_bytes()
            if not data or len(data) > 10 * 1024 * 1024 or not data.startswith(signature):
                missing.append(str(row['id']))
                continue

            key = f"certifications/{row['trainer_id']}/{uuid.uuid4()}{ext}"
            r2_key = put_certificate(key, data, mime_type, UPLOAD_DIR)
            conn.execute('UPDATE trainer_certifications SET storage_key = %s WHERE id = %s',
                         (r2_key, row['id']))
            moved += 1

    print(f'Certificados trasladados a R2: {moved}')
    if missing:
        print(f'Certificados que requieren revisión o una nueva carga: {len(missing)}')
        for certification_id in missing:
            print(f'- {certification_id}')


if __name__ == '__main__':
    main()
