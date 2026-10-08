"""Create fixture databases on PostgreSQL from a single init script.

Usage:
  .venv\\Scripts\\python.exe scripts\\load_fixtures.py

Uses fixtures/init_all.sql (all 6 demo databases in one file).
"""

from __future__ import annotations

import asyncio
import os
import re
import subprocess
import sys
from pathlib import Path

import asyncpg

HOST = os.getenv("DATABASE_HOST", "159.75.33.167")
PORT = int(os.getenv("DATABASE_PORT", "5432"))
USER = os.getenv("DATABASE_USER", "root")
PASSWORD = os.getenv("DATABASE_PASSWORD", "123456")

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
INIT_SQL = FIXTURES / "init_all.sql"


def parse_init_all(path: Path) -> list[tuple[str, str]]:
    """Split init_all.sql into (database_name, schema_sql) sections."""
    text = path.read_text(encoding="utf-8")
    sections: list[tuple[str, str]] = []
    blocks = re.split(r"\n-- =+\n-- DATABASE: ", text)
    for block in blocks[1:]:
        db_name, _, rest = block.partition("\n")
        db_name = db_name.strip()
        connect = re.search(r"\\c\s+\w+\s*\n", rest)
        if not connect:
            raise ValueError(f"Missing \\c directive for database {db_name!r}")
        schema = rest[connect.end() :].strip()
        sections.append((db_name, schema))
    return sections


def split_sql_statements(sql: str) -> list[str]:
    """Split SQL script into statements, respecting dollar-quotes and comments."""
    statements: list[str] = []
    buf: list[str] = []
    i = 0
    n = len(sql)
    in_single = False
    in_double = False
    in_line_comment = False
    in_block_comment = False
    dollar_tag: str | None = None

    while i < n:
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ""

        if in_line_comment:
            buf.append(ch)
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue

        if in_block_comment:
            buf.append(ch)
            if ch == "*" and nxt == "/":
                buf.append(nxt)
                i += 2
                in_block_comment = False
                continue
            i += 1
            continue

        if dollar_tag is not None:
            if sql.startswith(dollar_tag, i):
                buf.append(dollar_tag)
                i += len(dollar_tag)
                dollar_tag = None
                continue
            buf.append(ch)
            i += 1
            continue

        if in_single:
            buf.append(ch)
            if ch == "'" and nxt == "'":
                buf.append(nxt)
                i += 2
                continue
            if ch == "'":
                in_single = False
            i += 1
            continue

        if in_double:
            buf.append(ch)
            if ch == '"':
                in_double = False
            i += 1
            continue

        if ch == "-" and nxt == "-":
            buf.append(ch)
            buf.append(nxt)
            i += 2
            in_line_comment = True
            continue
        if ch == "/" and nxt == "*":
            buf.append(ch)
            buf.append(nxt)
            i += 2
            in_block_comment = True
            continue
        if ch == "'":
            in_single = True
            buf.append(ch)
            i += 1
            continue
        if ch == '"':
            in_double = True
            buf.append(ch)
            i += 1
            continue
        if ch == "$":
            m = re.match(r"\$[A-Za-z0-9_]*\$", sql[i:])
            if m:
                dollar_tag = m.group(0)
                buf.append(dollar_tag)
                i += len(dollar_tag)
                continue

        if ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            i += 1
            continue

        buf.append(ch)
        i += 1

    tail = "".join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


async def recreate_database(admin: asyncpg.Connection, db_name: str) -> None:
    await admin.execute(
        """
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = $1 AND pid <> pg_backend_pid()
        """,
        db_name,
    )
    await admin.execute(f'DROP DATABASE IF EXISTS "{db_name}"')
    await admin.execute(f'CREATE DATABASE "{db_name}"')
    print(f"  created database: {db_name}")


async def load_one(db_name: str, schema_sql: str) -> None:
    print(f"\n==> Loading {db_name}")
    statements = split_sql_statements(schema_sql)
    print(f"  statements: {len(statements)}")

    admin = await asyncpg.connect(
        host=HOST, port=PORT, user=USER, password=PASSWORD, database="postgres"
    )
    try:
        await recreate_database(admin, db_name)
    finally:
        await admin.close()

    conn = await asyncpg.connect(
        host=HOST, port=PORT, user=USER, password=PASSWORD, database=db_name
    )
    try:
        for idx, stmt in enumerate(statements, 1):
            try:
                await conn.execute(stmt)
            except Exception as e:
                preview = " ".join(stmt.split())[:120]
                raise RuntimeError(f"Failed at statement #{idx}: {preview}\n{e}") from e

        tables = await conn.fetchval(
            """
            SELECT count(*)
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            """
        )
        print(f"  OK: {tables} tables in {db_name}")
    finally:
        await conn.close()


def load_via_psql() -> int:
    """Fallback: run init_all.sql with psql when available."""
    env = os.environ.copy()
    env["PGPASSWORD"] = PASSWORD
    cmd = [
        "psql",
        "-h",
        HOST,
        "-p",
        str(PORT),
        "-U",
        USER,
        "-f",
        str(INIT_SQL),
    ]
    print(f"Running: {' '.join(cmd)}")
    return subprocess.call(cmd, env=env)


async def main() -> int:
    if not INIT_SQL.exists():
        print(f"Missing file: {INIT_SQL}", file=sys.stderr)
        return 1

    print(f"Connecting to {HOST}:{PORT} as {USER} ...")
    try:
        admin = await asyncpg.connect(
            host=HOST,
            port=PORT,
            user=USER,
            password=PASSWORD,
            database="postgres",
            timeout=15,
        )
        version = await admin.fetchval("SELECT version()")
        print(f"Connected: {version[:70]}...")
        await admin.close()
    except Exception as e:
        print(f"Connection failed: {e}", file=sys.stderr)
        return 1

    sections = parse_init_all(INIT_SQL)
    expected = [
        "blog_small",
        "ecommerce_medium",
        "saas_crm_large",
        "hr_system",
        "hospital_care",
        "security_ops",
    ]
    names = [name for name, _ in sections]
    if names != expected:
        print(f"Warning: parsed databases {names}, expected {expected}", file=sys.stderr)

    for db_name, schema_sql in sections:
        await load_one(db_name, schema_sql)

    print("\nAll fixture databases loaded from init_all.sql.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
