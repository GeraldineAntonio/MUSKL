"""Apply the numbered SQL migrations once, in order, to DATABASE_URL.

Safe to run at cloud service startup: each migration is recorded only after it
commits, and an advisory lock prevents concurrent instances racing migrations.
The target database must be empty on its first run.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import psycopg


DATABASE_URL = os.environ["DATABASE_URL"]
MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "db"
MIGRATION_NAME = re.compile(r"^(\d{3})_[a-z0-9_]+\.sql$")
LOCK_ID = 0x4D55534B4C  # Stable advisory lock key: "MUSKL".


def main() -> None:
    files = sorted(
        path
        for path in MIGRATIONS_DIR.iterdir()
        if MIGRATION_NAME.match(path.name)
    )
    if not files:
        raise SystemExit(f"No hay migraciones SQL en {MIGRATIONS_DIR}.")

    with psycopg.connect(DATABASE_URL, connect_timeout=15, autocommit=True) as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS muskl_schema_migrations (
                   version text PRIMARY KEY,
                   applied_at timestamptz NOT NULL DEFAULT now()
               )"""
        )
        for path in files:
            version = path.stem.split("_", maxsplit=1)[0]
            sql = path.read_text(encoding="utf-8")
            # Transaction-scoped locks work with Neon/PgBouncer transaction
            # pooling. Check the version after taking the lock so concurrent
            # Render starts cannot both apply the same migration.
            with conn.transaction():
                conn.execute("SELECT pg_advisory_xact_lock(%s)", (LOCK_ID,))
                already_applied = conn.execute(
                    "SELECT 1 FROM muskl_schema_migrations WHERE version = %s",
                    (version,),
                ).fetchone()
                if already_applied:
                    print(f"Ya aplicada: {path.name}")
                    continue
                conn.execute(sql)
                conn.execute(
                    "INSERT INTO muskl_schema_migrations (version) VALUES (%s)",
                    (version,),
                )
            print(f"Aplicada: {path.name}")


if __name__ == "__main__":
    main()
