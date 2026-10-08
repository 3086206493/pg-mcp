"""Query orchestrator for coordinating the complete query flow.

This module provides the QueryOrchestrator class that coordinates all components
of the query processing pipeline: SQL generation, validation, execution, and result
validation. It implements retry logic, error handling, and request tracking.
"""

from __future__ import annotations

import logging
import time
from typing import Any

from asyncpg import Pool

from pg_mcp.cache.schema_cache import SchemaCache
from pg_mcp.config.settings import ResilienceConfig, ValidationConfig
from pg_mcp.models.errors import (
    DatabaseError,
    ErrorCode,
    LLMError,
    LLMTimeoutError,
    LLMUnavailableError,
    PgMcpError,
    RateLimitExceededError,
    SchemaLoadError,
    SecurityViolationError,
    SQLParseError,
)
from pg_mcp.models.query import (
    ErrorDetail,
    QueryRequest,
    QueryResponse,
    QueryResult,
    ReturnType,
    ValidationResult,
)
from pg_mcp.observability.metrics import MetricsCollector
from pg_mcp.observability.tracing import request_context
from pg_mcp.resilience.circuit_breaker import CircuitBreaker
from pg_mcp.resilience.rate_limiter import MultiRateLimiter
from pg_mcp.resilience.retry import retry_async, sleep_before_retry
from pg_mcp.services.result_validator import ResultValidator
from pg_mcp.services.sql_executor import SQLExecutor
from pg_mcp.services.sql_generator import SQLGenerationResult, SQLGenerator
from pg_mcp.services.sql_validator import SQLValidator

logger = logging.getLogger(__name__)


class QueryOrchestrator:
    """Orchestrates the complete query processing pipeline.

    Coordinates SQL generation, validation, execution, and result validation with
    multi-database executor routing, rate limiting, retry/backoff, and metrics.
    """

    def __init__(
        self,
        sql_generator: SQLGenerator,
        sql_validator: SQLValidator,
        result_validator: ResultValidator,
        schema_cache: SchemaCache,
        pools: dict[str, Pool],
        resilience_config: ResilienceConfig,
        validation_config: ValidationConfig,
        sql_executors: dict[str, SQLExecutor] | None = None,
        sql_executor: SQLExecutor | None = None,
        rate_limiter: MultiRateLimiter | None = None,
        metrics: MetricsCollector | None = None,
        circuit_breaker: CircuitBreaker | None = None,
    ) -> None:
        """Initialize query orchestrator.

        Args:
            sql_generator: SQL generation service.
            sql_validator: SQL validation service.
            result_validator: Result validation service.
            schema_cache: Schema cache instance.
            pools: Dictionary mapping database names to connection pools.
            resilience_config: Resilience configuration for retries and circuit breaker.
            validation_config: Validation configuration including thresholds.
            sql_executors: Per-database SQL executors (preferred).
            sql_executor: Legacy single executor used for all DBs when
                ``sql_executors`` is not provided (keeps unit tests working).
            rate_limiter: Optional multi-resource rate limiter.
            metrics: Optional metrics collector.
            circuit_breaker: Optional shared circuit breaker (created if omitted).
        """
        self.sql_generator = sql_generator
        self.sql_validator = sql_validator
        self.result_validator = result_validator
        self.schema_cache = schema_cache
        self.pools = pools
        self.resilience_config = resilience_config
        self.validation_config = validation_config
        self.rate_limiter = rate_limiter
        self.metrics = metrics

        if sql_executors is not None:
            self.sql_executors = sql_executors
        elif sql_executor is not None:
            # Backward-compatible: one executor serves every configured pool key
            self.sql_executors = {name: sql_executor for name in pools} or {
                "_default": sql_executor
            }
        else:
            raise ValueError("Either sql_executors or sql_executor must be provided")

        # Keep legacy attribute for older call sites / tests
        self.sql_executor = sql_executor or next(iter(self.sql_executors.values()), None)

        self.circuit_breaker = circuit_breaker or CircuitBreaker(
            failure_threshold=resilience_config.circuit_breaker_threshold,
            recovery_timeout=resilience_config.circuit_breaker_timeout,
        )

    def _get_executor(self, database_name: str) -> SQLExecutor:
        """Select the SQL executor for a resolved database name."""
        executor = self.sql_executors.get(database_name)
        if executor is None:
            raise DatabaseError(
                message=f"No SQL executor configured for database '{database_name}'",
                details={
                    "database": database_name,
                    "available_executors": list(self.sql_executors.keys()),
                },
            )
        return executor

    async def execute_query(self, request: QueryRequest) -> QueryResponse:
        """Execute complete query flow from question to results."""
        async with request_context() as request_id:
            return await self._execute_query_inner(request, request_id)

    async def _execute_query_inner(
        self, request: QueryRequest, request_id: str
    ) -> QueryResponse:
        """Inner query flow with an established request_id context."""
        start_time = time.perf_counter()
        database_name = "unknown"
        logger.info(
            "Starting query execution",
            extra={"request_id": request_id, "question": request.question[:100]},
        )

        try:
            # Enforce max question length before any LLM call
            max_len = self.validation_config.max_question_length
            if len(request.question) > max_len:
                raise PgMcpError(
                    message=(
                        f"Question exceeds maximum length of {max_len} characters "
                        f"(got {len(request.question)})"
                    ),
                    code=ErrorCode.QUESTION_TOO_LONG,
                    details={
                        "max_question_length": max_len,
                        "actual_length": len(request.question),
                    },
                )

            database_name = self._resolve_database(request.database)
            logger.debug(
                "Resolved database",
                extra={"request_id": request_id, "database": database_name},
            )

            schema = self.schema_cache.get(database_name)
            if schema is None:
                pool = self.pools.get(database_name)
                if pool is None:
                    raise DatabaseError(
                        message=f"No connection pool available for database '{database_name}'",
                        details={"database": database_name},
                    )
                try:
                    schema = await self.schema_cache.load(database_name, pool)
                except Exception as e:
                    raise SchemaLoadError(
                        message=f"Failed to load schema for database '{database_name}': {e!s}",
                        details={"database": database_name, "error": str(e)},
                    ) from e

            generated_sql, validation_result, tokens_used = await self._generate_sql_with_retry(
                question=request.question,
                schema=schema,
                request_id=request_id,
            )

            if request.return_type == ReturnType.SQL:
                if self.metrics is not None:
                    self.metrics.increment_query_request("success", database_name)
                    self.metrics.query_duration.observe(time.perf_counter() - start_time)
                return QueryResponse(
                    success=True,
                    generated_sql=generated_sql,
                    validation=validation_result,
                    data=None,
                    error=None,
                    confidence=100,
                    tokens_used=tokens_used,
                )

            executor = self._get_executor(database_name)
            exec_started = time.perf_counter()
            results, total_count = await self._execute_with_rate_limit(executor, generated_sql)
            execution_time_ms = (time.perf_counter() - exec_started) * 1000

            if self.metrics is not None:
                self.metrics.observe_db_query_duration(execution_time_ms / 1000.0)

            logger.info(
                "SQL executed successfully",
                extra={
                    "request_id": request_id,
                    "database": database_name,
                    "row_count": total_count,
                    "execution_time_ms": execution_time_ms,
                },
            )

            result_confidence = await self._validate_results_safely(
                question=request.question,
                sql=generated_sql,
                results=results,
                row_count=total_count,
                request_id=request_id,
            )

            # Apply configured confidence threshold (warn via details, still return data)
            min_confidence = self.validation_config.min_confidence_score
            if result_confidence < min_confidence:
                logger.warning(
                    "Result confidence below configured threshold",
                    extra={
                        "request_id": request_id,
                        "confidence": result_confidence,
                        "min_confidence_score": min_confidence,
                    },
                )

            query_result = QueryResult(
                columns=list(results[0].keys()) if results else [],
                rows=results,
                row_count=len(results),
                execution_time_ms=execution_time_ms,
            )

            if self.metrics is not None:
                self.metrics.increment_query_request("success", database_name)
                self.metrics.query_duration.observe(time.perf_counter() - start_time)
                if tokens_used:
                    self.metrics.increment_llm_tokens("generate_sql", tokens_used)

            return QueryResponse(
                success=True,
                generated_sql=generated_sql,
                validation=validation_result,
                data=query_result,
                error=None,
                confidence=result_confidence,
                tokens_used=tokens_used,
            )

        except PgMcpError as e:
            logger.warning(
                "Query execution failed with known error",
                extra={
                    "request_id": request_id,
                    "error_code": e.code,
                    "error_message": str(e),
                },
            )
            if self.metrics is not None:
                status = "error"
                if e.code == ErrorCode.SECURITY_VIOLATION:
                    status = "rejected"
                    self.metrics.increment_sql_rejected(
                        (e.details or {}).get("reason", "security_violation")
                    )
                elif e.code == ErrorCode.RATE_LIMIT_EXCEEDED:
                    status = "rate_limited"
                self.metrics.increment_query_request(status, database_name)
                self.metrics.query_duration.observe(time.perf_counter() - start_time)

            return QueryResponse(
                success=False,
                generated_sql=None,
                validation=None,
                data=None,
                error=ErrorDetail(
                    code=e.code.value,
                    message=e.message,
                    details=e.details,
                ),
                confidence=0,
                tokens_used=None,
            )
        except Exception as e:
            logger.exception(
                "Query execution failed with unexpected error",
                extra={"request_id": request_id},
            )
            if self.metrics is not None:
                self.metrics.increment_query_request("error", database_name)
                self.metrics.query_duration.observe(time.perf_counter() - start_time)
            return QueryResponse(
                success=False,
                generated_sql=None,
                validation=None,
                data=None,
                error=ErrorDetail(
                    code=ErrorCode.INTERNAL_ERROR.value,
                    message=f"Internal server error: {e!s}",
                    details={"error_type": type(e).__name__},
                ),
                confidence=0,
                tokens_used=None,
            )

    async def _execute_with_rate_limit(
        self, executor: SQLExecutor, sql: str
    ) -> tuple[list[dict[str, Any]], int]:
        """Execute SQL under the query rate limiter when configured."""
        if self.rate_limiter is None:
            return await executor.execute(sql)

        timeout = self.resilience_config.rate_limit_timeout
        try:
            async with self.rate_limiter.for_queries(timeout=timeout):
                return await executor.execute(sql)
        except TimeoutError as e:
            raise RateLimitExceededError(
                message="Query rate limit exceeded: too many concurrent database operations",
                details={
                    "resource": "query",
                    "timeout": timeout,
                    "stats": self.rate_limiter.get_all_stats(),
                },
            ) from e

    def _resolve_database(self, database: str | None) -> str:
        """Resolve database name from request or auto-select."""
        if database is not None:
            if database not in self.pools:
                raise DatabaseError(
                    message=f"Database '{database}' not found",
                    details={
                        "requested_database": database,
                        "available_databases": list(self.pools.keys()),
                    },
                )
            return database

        available_dbs = list(self.pools.keys())
        if len(available_dbs) == 0:
            raise DatabaseError(message="No databases configured", details={})
        if len(available_dbs) == 1:
            return available_dbs[0]

        raise DatabaseError(
            message="Multiple databases available, please specify which to query",
            details={"available_databases": available_dbs},
        )

    async def _generate_sql_with_retry(
        self,
        question: str,
        schema: Any,
        request_id: str,
    ) -> tuple[str, ValidationResult, int | None]:
        """Generate and validate SQL with retry + exponential backoff."""
        if not self.circuit_breaker.allow_request():
            raise LLMError(
                message="SQL generation service is temporarily unavailable (circuit breaker open)",
                details={
                    "circuit_state": self.circuit_breaker.state,
                    "failure_count": self.circuit_breaker.failure_count,
                },
            )

        previous_sql: str | None = None
        error_feedback: str | None = None
        max_retries = self.resilience_config.max_retries
        tokens_used: int | None = None

        for attempt in range(max_retries + 1):
            try:
                if attempt > 0:
                    await sleep_before_retry(
                        attempt - 1,
                        self.resilience_config,
                        reason="sql_validation_retry",
                    )

                logger.debug(
                    "Generating SQL",
                    extra={
                        "request_id": request_id,
                        "attempt": attempt + 1,
                        "max_retries": max_retries + 1,
                    },
                )

                generation = await self._generate_with_rate_limit(
                    question=question,
                    schema=schema,
                    previous_sql=previous_sql,
                    error_feedback=error_feedback,
                )
                generated_sql = generation.sql
                tokens_used = (tokens_used or 0) + generation.tokens_used

                if self.metrics is not None:
                    self.metrics.increment_llm_call("generate_sql")

                try:
                    self.sql_validator.validate_or_raise(generated_sql)
                except (SecurityViolationError, SQLParseError) as validation_error:
                    if self.metrics is not None:
                        reason = (
                            "security_violation"
                            if isinstance(validation_error, SecurityViolationError)
                            else "sql_parse_error"
                        )
                        self.metrics.increment_sql_rejected(reason)

                    if attempt < max_retries:
                        logger.warning(
                            "SQL validation failed, retrying with feedback",
                            extra={
                                "request_id": request_id,
                                "attempt": attempt + 1,
                                "error": str(validation_error),
                            },
                        )
                        previous_sql = generated_sql
                        error_feedback = str(validation_error)
                        continue

                    self.circuit_breaker.record_failure()
                    logger.error(
                        "SQL validation failed after all retries",
                        extra={
                            "request_id": request_id,
                            "attempts": attempt + 1,
                            "error": str(validation_error),
                        },
                    )
                    raise

                self.circuit_breaker.record_success()
                validation_result = ValidationResult(
                    is_valid=True,
                    is_select=True,
                    allows_data_modification=False,
                    uses_blocked_functions=[],
                    error_message=None,
                )
                return generated_sql, validation_result, tokens_used

            except (LLMError, SecurityViolationError, SQLParseError, RateLimitExceededError):
                raise
            except Exception as e:
                self.circuit_breaker.record_failure()
                logger.exception(
                    "Unexpected error during SQL generation",
                    extra={"request_id": request_id},
                )
                raise LLMError(
                    message=f"SQL generation failed unexpectedly: {e!s}",
                    details={"error_type": type(e).__name__},
                ) from e

        self.circuit_breaker.record_failure()
        raise LLMError(
            message="SQL generation failed after all retry attempts",
            details={"max_retries": max_retries},
        )

    async def _generate_with_rate_limit(
        self,
        question: str,
        schema: Any,
        previous_sql: str | None,
        error_feedback: str | None,
    ) -> SQLGenerationResult:
        """Call the SQL generator under rate limit and transient-failure retries."""

        async def _call_generator() -> SQLGenerationResult:
            if self.rate_limiter is None:
                return await self.sql_generator.generate(
                    question=question,
                    schema=schema,
                    previous_attempt=previous_sql,
                    error_feedback=error_feedback,
                )

            timeout = self.resilience_config.rate_limit_timeout
            try:
                async with self.rate_limiter.for_llm(timeout=timeout):
                    return await self.sql_generator.generate(
                        question=question,
                        schema=schema,
                        previous_attempt=previous_sql,
                        error_feedback=error_feedback,
                    )
            except TimeoutError as e:
                raise RateLimitExceededError(
                    message="LLM rate limit exceeded: too many concurrent LLM calls",
                    details={
                        "resource": "llm",
                        "timeout": timeout,
                        "stats": self.rate_limiter.get_all_stats(),
                    },
                ) from e

        llm_started = time.perf_counter()
        try:
            return await retry_async(
                _call_generator,
                config=self.resilience_config,
                retry_on=(LLMUnavailableError, LLMTimeoutError),
                operation="llm_generate_sql",
            )
        finally:
            if self.metrics is not None:
                self.metrics.observe_llm_latency(
                    "generate_sql", time.perf_counter() - llm_started
                )

    async def _validate_results_safely(
        self,
        question: str,
        sql: str,
        results: list[dict[str, Any]],
        row_count: int,
        request_id: str,
    ) -> int:
        """Validate query results with error handling (non-blocking)."""
        if not self.validation_config.enabled:
            return 100

        try:
            if self.metrics is not None:
                self.metrics.increment_llm_call("validate_result")

            validation_result = await self.result_validator.validate(
                question=question,
                sql=sql,
                results=results,
                row_count=row_count,
            )

            logger.info(
                "Result validation completed",
                extra={
                    "request_id": request_id,
                    "confidence": validation_result.confidence,
                    "is_acceptable": validation_result.is_acceptable,
                },
            )
            return validation_result.confidence

        except Exception as e:
            logger.warning(
                "Result validation failed, continuing with default confidence",
                extra={"request_id": request_id, "error": str(e)},
            )
            # Do not mask failures as perfect confidence
            return self.validation_config.min_confidence_score

    @staticmethod
    def _get_current_time_ms() -> float:
        """Get current time in milliseconds."""
        return time.time() * 1000
