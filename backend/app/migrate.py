"""Apply the numbered SQL migrations once, in order, to DATABASE_URL."""

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
        conn.execute("SELECT pg_advisory_lock(%s)", (LOCK_ID,))
        try:
            conn.execute(
                """CREATE TABLE IF NOT EXISTS muskl_schema_migrations (
                       version text PRIMARY KEY,
                       applied_at timestamptz NOT NULL DEFAULT now()
                   )"""
            )
            applied = {
                row[0]
                for row in conn.execute(
                    "SELECT version FROM muskl_schema_migrations"
                ).fetchall()
            }
            for path in files:
                version = path.stem.split("_", maxsplit=1)[0]
                if version in applied:
                    print(f"Ya aplicada: {path.name}")
                    continue
                sql = path.read_text(encoding="utf-8")
                with conn.transaction():
                    conn.execute(sql)
                    conn.execute(
                        "INSERT INTO muskl_schema_migrations (version) VALUES (%s)",
                        (version,),
                    )
                print(f"Aplicada: {path.name}")
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", (LOCK_ID,))


if __name__ == "__main__":
    main()
