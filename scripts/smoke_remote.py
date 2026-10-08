"""Smoke-test remote multi-DB connectivity using project .env."""

from __future__ import annotations

import asyncio

from dotenv import load_dotenv

from pg_mcp.cache.schema_cache import SchemaCache
from pg_mcp.config.settings import get_settings, reset_settings
from pg_mcp.db.pool import close_pools, create_pools


async def main() -> None:
    load_dotenv()
    reset_settings()
    settings = get_settings()
    print("HOST:", settings.database.host)
    print("USER:", settings.database.user)
    print("PWD set:", bool(settings.database.password))
    print("DBS:", [db.name for db in settings.databases])
    print("blocked_tables:", settings.security.blocked_tables)

    pools = await create_pools(settings.databases)
    cache = SchemaCache(settings.cache)
    try:
        for name, pool in pools.items():
            schema = await cache.load(name, pool)
            live = await pool.fetchval(
                "SELECT count(*) FROM information_schema.tables "
                "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
            )
            print(f"  {name}: schema={len(schema.tables)} live={live}")
    finally:
        await close_pools(pools)
    print("SMOKE OK")


if __name__ == "__main__":
    asyncio.run(main())
