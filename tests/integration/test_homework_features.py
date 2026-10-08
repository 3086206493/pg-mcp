"""Integration-style tests for homework deliverables (multi-DB + security)."""

import pytest

from pg_mcp.config.settings import SecurityConfig
from pg_mcp.models.errors import SecurityViolationError
from pg_mcp.services.sql_validator import SQLValidator


class TestHomeworkSecurityIntegration:
    """Verify security controls end-to-end at validator layer (no LLM)."""

    @pytest.fixture
    def validator(self) -> SQLValidator:
        return SQLValidator(
            config=SecurityConfig(allow_write_operations=False),
            blocked_tables=["user_sessions", "api_keys"],
            blocked_columns=["users.password_hash"],
            allow_explain=False,
        )

    def test_blocked_table_user_sessions(self, validator: SQLValidator) -> None:
        with pytest.raises(SecurityViolationError) as exc_info:
            validator.validate_or_raise("SELECT * FROM user_sessions")
        assert exc_info.value.code.value == "security_violation"

    def test_blocked_column_password_hash(self, validator: SQLValidator) -> None:
        with pytest.raises(SecurityViolationError):
            validator.validate_or_raise("SELECT password_hash FROM users")

    def test_explain_rejected(self, validator: SQLValidator) -> None:
        with pytest.raises(SecurityViolationError) as exc_info:
            validator.validate_or_raise("EXPLAIN SELECT * FROM users")
        assert "EXPLAIN" in str(exc_info.value)


class TestHomeworkMultiDatabaseConfig:
    """Verify multi-database settings resolve correctly."""

    def test_database_names_list(self) -> None:
        from pg_mcp.config.settings import DatabaseConfig, OpenAIConfig, Settings

        settings = Settings(
            openai=OpenAIConfig(api_key="sk-test-key-12345"),
            database=DatabaseConfig(
                host="localhost",
                user="root",
                password="123456",
                name="blog_small",
            ),
            database_names="blog_small,ecommerce_medium",
            _env_file=None,
        )
        names = [db.name for db in settings.databases]
        assert names == ["blog_small", "ecommerce_medium"]
