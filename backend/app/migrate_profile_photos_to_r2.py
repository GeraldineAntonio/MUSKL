"""Move existing client profile photos from Neon bytea columns to private R2."""

from __future__ import annotations

import os
import uuid

import psycopg
from psycopg.rows import dict_row

from app.object_storage import configured, put_profile_photo


DATABASE_URL = os.environ['DATABASE_URL']


def main() -> None:
    if not configured():
        raise SystemExit('Configura las variables MUSKL_R2_* y el bucket privado primero.')

    moved = 0
    skipped = 0
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        rows = conn.execute("""SELECT cp.user_id, cp.profile_photo, cp.profile_photo_mime
            FROM client_profiles cp JOIN users u ON u.id = cp.user_id
            WHERE cp.profile_photo IS NOT NULL AND u.profile_photo_storage_key IS NULL
            ORDER BY cp.user_id""").fetchall()
        for row in rows:
            data = bytes(row['profile_photo'])
            mime = row['profile_photo_mime']
            signature = b'\xff\xd8\xff' if mime == 'image/jpeg' else b'\x89PNG\r\n\x1a\n'
            if mime not in ('image/jpeg', 'image/png') or not data.startswith(signature) or len(data) > 2 * 1024 * 1024:
                print(f"Revisar foto del usuario {row['user_id']}: formato, firma o tamaño inválido.")
                skipped += 1
                continue

            extension = 'jpg' if mime == 'image/jpeg' else 'png'
            key = f"profile-photos/{row['user_id']}/{uuid.uuid4()}.{extension}"
            storage_key = put_profile_photo(key, data, mime)
            # Clear the database binary in the same transaction that records its R2 key.
            conn.execute("""UPDATE users SET profile_photo_storage_key = %s,
                profile_photo_mime = %s, updated_at = now()
                WHERE id = %s AND profile_photo_storage_key IS NULL""",
                (storage_key, mime, row['user_id']))
            conn.execute("""UPDATE client_profiles
                SET profile_photo = NULL, profile_photo_mime = NULL, updated_at = now()
                WHERE user_id = %s""", (row['user_id'],))
            moved += 1

    print(f'Fotos trasladadas a R2: {moved}; requieren revisión: {skipped}.')


if __name__ == '__main__':
    main()
