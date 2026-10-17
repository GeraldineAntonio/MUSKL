from __future__ import annotations

import getpass
import hashlib
import os
import secrets


def main() -> None:
    database_url = os.environ.get('DATABASE_URL') or getpass.getpass(
        'URL de conexión de PostgreSQL/Neon (entrada oculta): '
    )
    if not database_url.strip():
        raise SystemExit('La URL de PostgreSQL es obligatoria.')
    os.environ['DATABASE_URL'] = database_url.strip()
    # This one-off script does not issue sessions. Generate a temporary key
    # when run outside the API container so the database URL is all it needs.
    os.environ.setdefault('JWT_SECRET', secrets.token_hex(32))

    from .main import GYM_ID, _create_user, pool

    first_name = input('Nombre del administrador: ').strip()
    last_name = input('Apellido: ').strip()
    email = input('Correo: ').strip().lower()
    password = getpass.getpass('Contraseña (mínimo 8 caracteres): ')
    confirmation = getpass.getpass('Confirmar contraseña: ')
    if not first_name or not last_name or '@' not in email:
        raise SystemExit('Nombre, apellido y correo válidos son obligatorios.')
    if len(password) < 8 or password != confirmation:
        raise SystemExit('La contraseña debe tener 8 caracteres y coincidir.')

    pool.open(wait=True)
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                active_admin = cur.execute(
                    "SELECT 1 FROM users WHERE gym_id = %s AND role = 'admin' AND status = 'active' LIMIT 1",
                    (GYM_ID,),
                ).fetchone()
                if active_admin:
                    raise SystemExit('Ya existe un administrador activo; no se creó otro.')
                user = _create_user(
                    cur,
                    role='admin',
                    status='active',
                    first_name=first_name,
                    last_name=last_name,
                    email=email,
                    phone=None,
                    password=password,
                )
                invite = f'MSK-ADM-{secrets.token_urlsafe(12).upper()}'
                token_hash = hashlib.sha256(invite.encode()).hexdigest()
                cur.execute(
                    """INSERT INTO admin_invite_tokens (gym_id, token_hash, label, created_by, expires_at)
                       VALUES (%s, %s, %s, %s, now() + interval '30 days')""",
                    (GYM_ID, token_hash, 'Token inicial de bootstrap', user['id']),
                )
        print(f'Administrador creado: {email}')
        print('Token inicial para otro admin (guárdalo; solo se muestra una vez):')
        print(invite)
    finally:
        pool.close()


if __name__ == '__main__':
    main()
