"""Unit tests for ResultValidator."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pydantic import SecretStr

from pg_mcp.config.settings import OpenAIConfig, ValidationConfig
from pg_mcp.services.result_validator import ResultValidator


@pytest.fixture
def validator() -> ResultValidator:
    return ResultValidator(
        OpenAIConfig(api_key=SecretStr("sk-test-key-12345")),
        ValidationConfig(min_confidence_score=70, enabled=True),
    )


class TestResultValidator:
    @pytest.mark.asyncio
    async def test_validate_disabled(self) -> None:
        rv = ResultValidator(
            OpenAIConfig(api_key=SecretStr("sk-test-key-12345")),
            ValidationConfig(enabled=False),
        )
        result = await rv.validate(
            question="Count users",
            sql="SELECT COUNT(*) FROM users",
            results=[{"count": 1}],
            row_count=1,
        )
        assert result.confidence == 100
        assert result.is_acceptable is True

    @pytest.mark.asyncio
    async def test_validate_success(self, validator: ResultValidator) -> None:
        mock_response = MagicMock()
        mock_response.choices = [
            MagicMock(
                message=MagicMock(
                    content='{"confidence": 88, "explanation": "Looks correct", "suggestion": null}'
                )
            )
        ]

        with patch.object(
            validator.client.chat.completions,
            "create",
            new=AsyncMock(return_value=mock_response),
        ):
            result = await validator.validate(
                question="How many users?",
                sql="SELECT COUNT(*) FROM users",
                results=[{"count": 42}],
                row_count=1,
            )

        assert result.confidence == 88
        assert result.is_acceptable is True
        assert "correct" in result.explanation.lower()

    @pytest.mark.asyncio
    async def test_validate_below_threshold(self, validator: ResultValidator) -> None:
        mock_response = MagicMock()
        mock_response.choices = [
            MagicMock(
                message=MagicMock(
                    content='{"confidence": 40, "explanation": "Mismatch", "suggestion": "Retry"}'
                )
            )
        ]

        with patch.object(
            validator.client.chat.completions,
            "create",
            new=AsyncMock(return_value=mock_response),
        ):
            result = await validator.validate(
                question="Top products",
                sql="SELECT * FROM users",
                results=[{"id": 1}],
                row_count=1,
            )

        assert result.confidence == 40
        assert result.is_acceptable is False
        assert result.suggestion == "Retry"
