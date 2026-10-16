"""Create the first admin in a remote database without echoing its URL."""

from __future__ import annotations

import getpass
import os


def main() -> None:
    database_url = getpass.getpass("Neon DATABASE_URL (no se mostrará): ").strip()
    if not database_url.startswith(("postgres://", "postgresql://")):
        raise SystemExit("La URL debe ser una conexión PostgreSQL válida.")

    os.environ["DATABASE_URL"] = database_url
    from .bootstrap_admin import main as create_admin

    create_admin()


if __name__ == "__main__":
    main()
