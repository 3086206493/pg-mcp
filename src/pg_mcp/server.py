"""FastMCP server for PostgreSQL natural language query interface.

This module implements the MCP server using FastMCP, exposing the query
functionality as an MCP tool. It includes complete lifespan management for
initializing and cleaning up all components.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from asyncpg import Pool
from mcp.server.fastmcp import FastMCP

from pg_mcp.cache.schema_cache import SchemaCache
from pg_mcp.config.settings import Settings
from pg_mcp.db.pool import close_pools, create_pools
from pg_mcp.models.query import QueryRequest, QueryResponse, ReturnType
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

# Global state for lifespan management
_settings: Settings | None = None
_pools: dict[str, Pool] | None = None
_schema_cache: SchemaCache | None = None
_orchestrator: QueryOrchestrator | None = None
_metrics: MetricsCollector | None = None
_circuit_breaker: CircuitBreaker | None = None
_rate_limiter: MultiRateLimiter | None = None


@asynccontextmanager
async def lifespan(_app: FastMCP) -> AsyncIterator[None]:  # type: ignore[type-arg]
    """Lifespan context manager for server initialization and cleanup."""
    global _settings, _pools, _schema_cache, _orchestrator, _metrics
    global _circuit_breaker, _rate_limiter

    logger.info("Starting PostgreSQL MCP Server initialization...")

    try:
        logger.info("Loading configuration...")
        from dotenv import load_dotenv

        load_dotenv()
        _settings = Settings()

        logger.info("Configuring logging...")
        configure_logging(
            level=_settings.observability.log_level,
            log_format=_settings.observability.log_format,
            enable_sensitive_filter=True,
        )

        logger.info(
            "Configuration loaded",
            extra={
                "environment": _settings.environment,
                "log_level": _settings.observability.log_level,
                "databases": [db.name for db in _settings.databases],
            },
        )

        # Multi-database pools via create_pools
        logger.info("Creating database connection pools...")
        db_configs = _settings.databases
        _pools = await create_pools(db_configs)
        for db_cfg in db_configs:
            logger.info(
                f"Created connection pool for database '{db_cfg.name}'",
                extra={
                    "min_size": db_cfg.min_pool_size,
                    "max_size": db_cfg.max_pool_size,
                },
            )

        logger.info("Initializing metrics collector...")
        _metrics = MetricsCollector()

        logger.info("Initializing schema cache...")
        _schema_cache = SchemaCache(_settings.cache, metrics=_metrics)

        for db_name, pool in _pools.items():
            logger.info(f"Loading schema for database '{db_name}'...")
            schema = await _schema_cache.load(db_name, pool)
            logger.info(
                f"Schema loaded for '{db_name}'",
                extra={"tables": len(schema.tables)},
            )

        if _settings.observability.metrics_enabled:
            _metrics.start_metrics_server(_settings.observability.metrics_port)
            logger.info(f"Metrics server started on port {_settings.observability.metrics_port}")

        logger.info("Initializing service components...")
        sql_generator = SQLGenerator(_settings.openai)

        sql_validator = SQLValidator(
            config=_settings.security,
            blocked_tables=_settings.security.blocked_tables or None,
            blocked_columns=_settings.security.blocked_columns or None,
            allow_explain=_settings.security.allow_explain,
        )

        # One executor per database (correct pool + config)
        sql_executors: dict[str, SQLExecutor] = {}
        config_by_name = {cfg.name: cfg for cfg in db_configs}
        for db_name, pool in _pools.items():
            executor = SQLExecutor(
                pool=pool,
                security_config=_settings.security,
                db_config=config_by_name[db_name],
            )
            sql_executors[db_name] = executor
            logger.info(f"Created SQL executor for database '{db_name}'")

        result_validator = ResultValidator(
            openai_config=_settings.openai,
            validation_config=_settings.validation,
        )

        logger.info("Initializing resilience components...")
        _circuit_breaker = CircuitBreaker(
            failure_threshold=_settings.resilience.circuit_breaker_threshold,
            recovery_timeout=_settings.resilience.circuit_breaker_timeout,
        )
        _rate_limiter = MultiRateLimiter(
            query_limit=_settings.resilience.max_concurrent_queries,
            llm_limit=_settings.resilience.max_concurrent_llm,
        )

        logger.info("Creating query orchestrator...")
        _orchestrator = QueryOrchestrator(
            sql_generator=sql_generator,
            sql_validator=sql_validator,
            sql_executors=sql_executors,
            result_validator=result_validator,
            schema_cache=_schema_cache,
            pools=_pools,
            resilience_config=_settings.resilience,
            validation_config=_settings.validation,
            rate_limiter=_rate_limiter,
            metrics=_metrics,
            circuit_breaker=_circuit_breaker,
        )

        logger.info("PostgreSQL MCP Server initialization complete!")
        logger.info(
            "Server ready to accept requests",
            extra={
                "databases": list(_pools.keys()),
                "cache_enabled": _settings.cache.enabled,
                "metrics_enabled": _settings.observability.metrics_enabled,
                "blocked_tables": _settings.security.blocked_tables,
                "allow_explain": _settings.security.allow_explain,
            },
        )

        yield

    finally:
        logger.info("Starting PostgreSQL MCP Server shutdown...")

        if _schema_cache is not None:
            try:
                import asyncio

                await asyncio.wait_for(_schema_cache.stop_auto_refresh(), timeout=3.0)
                logger.info("Schema auto-refresh stopped")
            except TimeoutError:
                logger.warning("Schema auto-refresh stop timed out")
            except Exception as e:
                logger.warning(f"Error stopping schema auto-refresh: {e!s}")

        if _pools is not None:
            try:
                await close_pools(_pools, timeout=5.0)
                logger.info("Database connection pools closed")
            except Exception as e:
                logger.error(f"Error closing connection pools: {e!s}")

        logger.info("PostgreSQL MCP Server shutdown complete")


mcp = FastMCP("pg-mcp", lifespan=lifespan, host="0.0.0.0", port=8000)


@mcp.tool()
async def query(
    question: str,
    database: str | None = None,
    return_type: str = "result",
) -> dict[str, Any]:
    """Execute a natural language query against PostgreSQL database.

    Converts natural language questions into SQL queries and executes them
    against the specified PostgreSQL database with security validation.

    Args:
        question: Natural language description of the query.
        database: Target database name (required when multiple DBs are configured).
        return_type: ``sql`` to return SQL only, ``result`` to execute (default).

    Returns:
        dict: Query response with success, generated_sql, data/error, confidence,
        and tokens_used.
    """
    global _orchestrator

    if _orchestrator is None:
        return {
            "success": False,
            "error": {
                "code": "SERVER_NOT_INITIALIZED",
                "message": "Server not initialized properly",
                "details": None,
            },
            "tokens_used": 0,
        }

    if return_type not in ("sql", "result"):
        return {
            "success": False,
            "error": {
                "code": "INVALID_PARAMETER",
                "message": f"Invalid return_type: '{return_type}'. Must be 'sql' or 'result'.",
                "details": {"return_type": return_type},
            },
            "tokens_used": 0,
        }

    try:
        request = QueryRequest(
            question=question,
            database=database,
            return_type=ReturnType(return_type),
        )
    except Exception as e:
        return {
            "success": False,
            "error": {
                "code": "INVALID_REQUEST",
                "message": f"Invalid request parameters: {e!s}",
                "details": {"error": str(e)},
            },
            "tokens_used": 0,
        }

    try:
        response: QueryResponse = await _orchestrator.execute_query(request)
        return response.to_dict()
    except Exception as e:
        logger.exception("Unexpected error in query tool")
        return {
            "success": False,
            "error": {
                "code": "INTERNAL_ERROR",
                "message": f"Internal server error: {e!s}",
                "details": {"error_type": type(e).__name__},
            },
            "tokens_used": 0,
        }


@mcp.tool()
async def health() -> dict[str, Any]:
    """Report server health: pools, circuit breaker, rate limiter, and cache."""
    databases: list[str] = list(_pools.keys()) if _pools else []
    pool_stats: dict[str, Any] = {}
    if _pools:
        for name, pool in _pools.items():
            pool_stats[name] = {
                "size": pool.get_size(),
                "idle": pool.get_idle_size(),
                "min": pool.get_min_size(),
                "max": pool.get_max_size(),
            }
            if _metrics is not None:
                _metrics.set_db_connections_active(name, pool.get_size() - pool.get_idle_size())

    cb_stats = _circuit_breaker.get_stats() if _circuit_breaker is not None else None
    rl_stats = _rate_limiter.get_all_stats() if _rate_limiter is not None else None
    cached = _schema_cache.get_cached_databases() if _schema_cache is not None else []
    if _schema_cache is not None and _metrics is not None:
        for db_name in cached:
            age = _schema_cache.get_cache_age(db_name)
            if age is not None:
                _metrics.set_schema_cache_age(db_name, age)

    healthy = bool(_orchestrator is not None and _pools)
    return {
        "status": "ok" if healthy else "degraded",
        "databases": databases,
        "pools": pool_stats,
        "circuit_breaker": cb_stats,
        "rate_limiter": rl_stats,
        "schema_cache": cached,
        "metrics_enabled": bool(_settings and _settings.observability.metrics_enabled),
    }


if __name__ == "__main__":
    """Run the server when executed directly."""
    import anyio

    anyio.run(mcp.run_stdio_async)
