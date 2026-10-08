"""HTTP demo server for pg-mcp (easier than stdio MCP for local demo).

Endpoints:
  GET  /health
  GET  /metrics  (redirect info; prometheus is on OBSERVABILITY_METRICS_PORT)
  POST /query    {"question":"...","database":"blog_small","return_type":"result"}

Usage:
  uv run python scripts/run_http_demo.py
"""

from __future__ import annotations

import json
from contextlib import asynccontextmanager
from typing import Any

from pathlib import Path

import uvicorn
from dotenv import load_dotenv
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import FileResponse, JSONResponse
from starlette.routing import Route

from pg_mcp.cache.schema_cache import SchemaCache
from pg_mcp.config.settings import Settings, get_settings, reset_settings
from pg_mcp.db.pool import close_pools, create_pools
from pg_mcp.models.query import QueryRequest, ReturnType
from pg_mcp.observability.logging import configure_logging, get_logger
from pg_mcp.observability.metrics import MetricsCollector
from pg_mcp.resilience.circuit_breaker import CircuitBreaker
from pg_mcp.resilience.rate_limiter import MultiRateLimiter
from pg_mcp.services.orchestrator import QueryOrchestrator
from pg_mcp.services.result_validator import ResultValidator
from pg_mcp.services.sql_executor import SQLExecutor
from pg_mcp.services.sql_generator import SQLGenerator
from pg_mcp.services.sql_validator import SQLValidator

logger = get_logger(__name__)

state: dict[str, Any] = {}


@asynccontextmanager
async def lifespan(_app: Starlette):
    load_dotenv()
    reset_settings()
    settings = get_settings()
    configure_logging(
        level=settings.observability.log_level,
        log_format=settings.observability.log_format,
        enable_sensitive_filter=True,
    )

    logger.info(
        "Starting HTTP demo",
        extra={
            "host": settings.database.host,
            "databases": [db.name for db in settings.databases],
        },
    )

    metrics = MetricsCollector()
    pools = await create_pools(settings.databases)
    schema_cache = SchemaCache(settings.cache, metrics=metrics)
    for name, pool in pools.items():
        await schema_cache.load(name, pool)
        logger.info(f"Schema loaded: {name}")

    if settings.observability.metrics_enabled:
        metrics.start_metrics_server(settings.observability.metrics_port)
        logger.info(f"Prometheus metrics on :{settings.observability.metrics_port}")

    sql_generator = SQLGenerator(settings.openai)
    sql_validator = SQLValidator(
        config=settings.security,
        blocked_tables=settings.security.blocked_tables or None,
        blocked_columns=settings.security.blocked_columns or None,
        allow_explain=settings.security.allow_explain,
    )
    sql_executors = {
        cfg.name: SQLExecutor(pool=pools[cfg.name], security_config=settings.security, db_config=cfg)
        for cfg in settings.databases
    }
    result_validator = ResultValidator(settings.openai, settings.validation)
    circuit_breaker = CircuitBreaker(
        failure_threshold=settings.resilience.circuit_breaker_threshold,
        recovery_timeout=settings.resilience.circuit_breaker_timeout,
    )
    rate_limiter = MultiRateLimiter(
        query_limit=settings.resilience.max_concurrent_queries,
        llm_limit=settings.resilience.max_concurrent_llm,
    )
    orchestrator = QueryOrchestrator(
        sql_generator=sql_generator,
        sql_validator=sql_validator,
        sql_executors=sql_executors,
        result_validator=result_validator,
        schema_cache=schema_cache,
        pools=pools,
        resilience_config=settings.resilience,
        validation_config=settings.validation,
        rate_limiter=rate_limiter,
        metrics=metrics,
        circuit_breaker=circuit_breaker,
    )

    state.update(
        {
            "settings": settings,
            "pools": pools,
            "schema_cache": schema_cache,
            "orchestrator": orchestrator,
            "circuit_breaker": circuit_breaker,
            "rate_limiter": rate_limiter,
            "metrics": metrics,
        }
    )
    logger.info("HTTP demo ready on http://127.0.0.1:8080")
    try:
        yield
    finally:
        await close_pools(pools, timeout=5.0)
        state.clear()
        logger.info("HTTP demo stopped")


async def health(_: Request) -> JSONResponse:
    settings: Settings = state["settings"]
    pools = state["pools"]
    cb = state["circuit_breaker"]
    rl = state["rate_limiter"]
    cache = state["schema_cache"]
    pool_stats = {
        name: {
            "size": pool.get_size(),
            "idle": pool.get_idle_size(),
        }
        for name, pool in pools.items()
    }
    return JSONResponse(
        {
            "status": "ok",
            "databases": list(pools.keys()),
            "db_host": settings.database.host,
            "pools": pool_stats,
            "circuit_breaker": cb.get_stats(),
            "rate_limiter": rl.get_all_stats(),
            "schema_cache": cache.get_cached_databases(),
            "blocked_tables": settings.security.blocked_tables,
            "allow_explain": settings.security.allow_explain,
            "metrics_port": settings.observability.metrics_port,
        }
    )


async def query(request: Request) -> JSONResponse:
    body = await request.json()
    question = body.get("question")
    if not question:
        return JSONResponse({"success": False, "error": {"message": "question required"}}, 400)

    database = body.get("database")
    return_type = body.get("return_type", "result")
    try:
        req = QueryRequest(
            question=question,
            database=database,
            return_type=ReturnType(return_type),
        )
    except Exception as e:
        return JSONResponse(
            {"success": False, "error": {"code": "INVALID_REQUEST", "message": str(e)}},
            400,
        )

    orchestrator: QueryOrchestrator = state["orchestrator"]
    response = await orchestrator.execute_query(req)
    return JSONResponse(response.to_dict())


STATIC_DIR = Path(__file__).resolve().parent / "static"


async def root(_: Request) -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


app = Starlette(
    debug=True,
    routes=[
        Route("/", root),
        Route("/health", health),
        Route("/query", query, methods=["POST"]),
    ],
    lifespan=lifespan,
)


def main() -> None:
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")


if __name__ == "__main__":
    main()
