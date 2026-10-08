"""Unit tests for MCP server tools (query, health)."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from pg_mcp.models.query import QueryResponse, ReturnType
from pg_mcp.resilience.circuit_breaker import CircuitBreaker
from pg_mcp.resilience.rate_limiter import MultiRateLimiter
from pg_mcp.services.orchestrator import QueryOrchestrator


@pytest.fixture
def restore_server_globals():
    """Save and restore server module globals."""
    import pg_mcp.server as server

    saved = {
        "_settings": server._settings,
        "_pools": server._pools,
        "_schema_cache": server._schema_cache,
        "_orchestrator": server._orchestrator,
        "_metrics": server._metrics,
        "_circuit_breaker": server._circuit_breaker,
        "_rate_limiter": server._rate_limiter,
    }
    yield server
    for key, value in saved.items():
        setattr(server, key, value)


class TestQueryTool:
    """Tests for the MCP query tool."""

    @pytest.mark.asyncio
    async def test_query_not_initialized(self, restore_server_globals) -> None:
        server = restore_server_globals
        server._orchestrator = None

        result = await server.query(question="How many users?", return_type="result")

        assert result["success"] is False
        assert result["error"]["code"] == "SERVER_NOT_INITIALIZED"
        assert result["tokens_used"] == 0

    @pytest.mark.asyncio
    async def test_query_invalid_return_type(self, restore_server_globals) -> None:
        server = restore_server_globals
        server._orchestrator = MagicMock()

        result = await server.query(question="test", return_type="invalid")

        assert result["success"] is False
        assert result["error"]["code"] == "INVALID_PARAMETER"

    @pytest.mark.asyncio
    async def test_query_success_delegates_to_orchestrator(self, restore_server_globals) -> None:
        server = restore_server_globals
        mock_orchestrator = AsyncMock(spec=QueryOrchestrator)
        mock_orchestrator.execute_query.return_value = QueryResponse(
            success=True,
            generated_sql="SELECT COUNT(*) FROM users",
            tokens_used=256,
        )
        server._orchestrator = mock_orchestrator

        result = await server.query(
            question="How many users?",
            database="blog_small",
            return_type="result",
        )

        assert result["success"] is True
        assert result["generated_sql"] == "SELECT COUNT(*) FROM users"
        assert result["tokens_used"] == 256
        mock_orchestrator.execute_query.assert_awaited_once()
        request = mock_orchestrator.execute_query.call_args.args[0]
        assert request.question == "How many users?"
        assert request.database == "blog_small"
        assert request.return_type == ReturnType.RESULT

    @pytest.mark.asyncio
    async def test_query_unexpected_exception(self, restore_server_globals) -> None:
        server = restore_server_globals
        mock_orchestrator = AsyncMock(spec=QueryOrchestrator)
        mock_orchestrator.execute_query.side_effect = RuntimeError("boom")
        server._orchestrator = mock_orchestrator

        result = await server.query(question="test", return_type="result")

        assert result["success"] is False
        assert result["error"]["code"] == "INTERNAL_ERROR"
        assert result["tokens_used"] == 0


class TestHealthTool:
    """Tests for the MCP health tool."""

    @pytest.mark.asyncio
    async def test_health_degraded_when_not_initialized(self, restore_server_globals) -> None:
        server = restore_server_globals
        server._orchestrator = None
        server._pools = None

        result = await server.health()

        assert result["status"] == "degraded"
        assert result["databases"] == []

    @pytest.mark.asyncio
    async def test_health_ok_with_components(self, restore_server_globals) -> None:
        server = restore_server_globals

        mock_pool = MagicMock()
        mock_pool.get_size.return_value = 4
        mock_pool.get_idle_size.return_value = 2
        mock_pool.get_min_size.return_value = 2
        mock_pool.get_max_size.return_value = 10

        mock_cache = MagicMock()
        mock_cache.get_cached_databases.return_value = ["blog_small"]
        mock_cache.get_cache_age.return_value = 12.5

        mock_metrics = MagicMock()
        mock_settings = MagicMock()
        mock_settings.observability.metrics_enabled = True

        server._orchestrator = MagicMock()
        server._pools = {"blog_small": mock_pool}
        server._schema_cache = mock_cache
        server._metrics = mock_metrics
        server._settings = mock_settings
        server._circuit_breaker = CircuitBreaker(failure_threshold=5, recovery_timeout=60.0)
        server._rate_limiter = MultiRateLimiter(query_limit=10, llm_limit=5)

        result = await server.health()

        assert result["status"] == "ok"
        assert result["databases"] == ["blog_small"]
        assert result["pools"]["blog_small"]["size"] == 4
        assert result["circuit_breaker"]["state"] == "closed"
        assert "queries" in result["rate_limiter"]
        assert result["schema_cache"] == ["blog_small"]
        mock_metrics.set_schema_cache_age.assert_called_once_with("blog_small", 12.5)


class TestServerLifespan:
    """Smoke test for lifespan wiring with heavy dependencies mocked."""

    @pytest.mark.asyncio
    async def test_lifespan_initializes_multi_db_executors(self) -> None:
        from pg_mcp.server import lifespan, mcp

        mock_pool = MagicMock()
        mock_schema = MagicMock()
        mock_schema.tables = []

        with (
            patch("pg_mcp.server.create_pools", new=AsyncMock(return_value={"db_a": mock_pool})),
            patch("pg_mcp.server.close_pools", new=AsyncMock()) as mock_close_pools,
            patch("pg_mcp.server.SchemaCache") as mock_cache_cls,
            patch("pg_mcp.server.MetricsCollector") as mock_metrics_cls,
            patch("pg_mcp.server.Settings") as mock_settings_cls,
            patch("pg_mcp.server.SQLGenerator"),
            patch("pg_mcp.server.SQLValidator"),
            patch("pg_mcp.server.SQLExecutor"),
            patch("pg_mcp.server.ResultValidator"),
            patch("pg_mcp.server.QueryOrchestrator") as mock_orch_cls,
            patch("pg_mcp.server.CircuitBreaker"),
            patch("pg_mcp.server.MultiRateLimiter"),
            patch("dotenv.load_dotenv"),
            patch("pg_mcp.server.configure_logging"),
        ):
            settings = MagicMock()
            db_cfg = MagicMock()
            db_cfg.name = "db_a"
            db_cfg.min_pool_size = 2
            db_cfg.max_pool_size = 10
            settings.databases = [db_cfg]
            settings.environment = "test"
            settings.observability.log_level = "INFO"
            settings.observability.log_format = "text"
            settings.observability.metrics_enabled = False
            settings.cache = MagicMock()
            settings.openai = MagicMock()
            settings.security = MagicMock()
            settings.security.blocked_tables = []
            settings.security.blocked_columns = []
            settings.security.allow_explain = False
            settings.resilience = MagicMock()
            settings.resilience.circuit_breaker_threshold = 5
            settings.resilience.circuit_breaker_timeout = 60.0
            settings.resilience.max_concurrent_queries = 10
            settings.resilience.max_concurrent_llm = 5
            settings.validation = MagicMock()
            mock_settings_cls.return_value = settings

            cache = MagicMock()
            cache.load = AsyncMock(return_value=mock_schema)
            cache.stop_auto_refresh = AsyncMock()
            mock_cache_cls.return_value = cache
            mock_metrics_cls.return_value = MagicMock()
            mock_orch_cls.return_value = MagicMock()

            async with lifespan(mcp):
                import pg_mcp.server as server

                assert server._orchestrator is not None
                assert "db_a" in server._pools
                assert server._schema_cache is cache
                mock_orch_cls.assert_called_once()

            mock_close_pools.assert_awaited_once()
