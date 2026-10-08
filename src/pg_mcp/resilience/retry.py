"""Retry helpers with exponential backoff.

Provides utilities for retrying transient failures using ResilienceConfig
settings (retry_delay, backoff_factor, max_retries).
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from typing import TypeVar

from pg_mcp.config.settings import ResilienceConfig

logger = logging.getLogger(__name__)

T = TypeVar("T")


def compute_backoff_delay(
    attempt: int,
    *,
    retry_delay: float,
    backoff_factor: float,
) -> float:
    """Compute exponential backoff delay for a zero-based attempt index.

    Args:
        attempt: Zero-based attempt number (0 = first retry after initial failure).
        retry_delay: Base delay in seconds.
        backoff_factor: Multiplier applied per attempt.

    Returns:
        Delay in seconds before the next attempt.
    """
    if retry_delay <= 0:
        return 0.0
    return retry_delay * (backoff_factor**attempt)


async def sleep_before_retry(
    attempt: int,
    config: ResilienceConfig,
    *,
    reason: str | None = None,
) -> None:
    """Sleep using exponential backoff before a retry attempt.

    Args:
        attempt: Zero-based index of the upcoming retry (0 after first failure).
        config: Resilience configuration.
        reason: Optional reason logged for observability.
    """
    delay = compute_backoff_delay(
        attempt,
        retry_delay=config.retry_delay,
        backoff_factor=config.backoff_factor,
    )
    if delay <= 0:
        return

    logger.debug(
        "Waiting before retry",
        extra={"attempt": attempt + 1, "delay_seconds": delay, "reason": reason},
    )
    await asyncio.sleep(delay)


async def retry_async(
    func: Callable[[], Awaitable[T]],
    *,
    config: ResilienceConfig,
    retry_on: tuple[type[BaseException], ...] = (Exception,),
    operation: str = "operation",
) -> T:
    """Execute an async callable with retries and exponential backoff.

    The initial attempt does not sleep. Subsequent attempts wait
    ``retry_delay * backoff_factor ** (attempt - 1)`` seconds.

    Args:
        func: Zero-argument async callable to execute.
        config: Resilience configuration controlling retries.
        retry_on: Exception types that trigger a retry.
        operation: Label used in log messages.

    Returns:
        The successful result of ``func``.

    Raises:
        The last exception if all attempts fail, or non-retryable exceptions
        immediately.
    """
    max_attempts = config.max_retries + 1
    last_error: BaseException | None = None

    for attempt in range(max_attempts):
        try:
            return await func()
        except retry_on as exc:
            last_error = exc
            if attempt >= config.max_retries:
                break
            logger.warning(
                "Transient failure, will retry",
                extra={
                    "operation": operation,
                    "attempt": attempt + 1,
                    "max_attempts": max_attempts,
                    "error": str(exc),
                },
            )
            await sleep_before_retry(attempt, config, reason=operation)

    assert last_error is not None
    raise last_error
