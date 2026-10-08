"""Configuration management for PostgreSQL MCP Server.

This module defines all configuration settings using Pydantic for validation
and type safety. Configuration is loaded from environment variables with
sensible defaults.
"""

from __future__ import annotations

import os
from typing import Any, Literal

from dotenv import load_dotenv
from pydantic import BaseModel, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _env(key: str, default: str | None = None) -> str | None:
    """Read from process environment only (call load_dotenv() before Settings)."""
    return os.environ.get(key, default)


class DatabaseConfig(BaseModel):
    """PostgreSQL database connection configuration."""

    host: str = Field(default="localhost", description="Database host")
    port: int = Field(default=5432, ge=1, le=65535, description="Database port")
    name: str = Field(default="postgres", description="Database name")
    user: str = Field(default="postgres", description="Database user")
    password: str = Field(default="", description="Database password")

    min_pool_size: int = Field(default=5, ge=1, le=100, description="Minimum pool size")
    max_pool_size: int = Field(default=20, ge=1, le=100, description="Maximum pool size")
    pool_timeout: float = Field(
        default=30.0, ge=1.0, le=300.0, description="Pool acquire timeout in seconds"
    )
    command_timeout: float = Field(
        default=30.0, ge=1.0, le=300.0, description="Command execution timeout in seconds"
    )

    @property
    def dsn(self) -> str:
        """Build PostgreSQL DSN connection string."""
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.name}"

    @property
    def safe_dsn(self) -> str:
        """Build DSN with masked password for logging."""
        return f"postgresql://{self.user}:***@{self.host}:{self.port}/{self.name}"

    def copy_with_name(self, name: str) -> DatabaseConfig:
        """Create a copy targeting a different database name."""
        return self.model_copy(update={"name": name})


class OpenAIConfig(BaseModel):
    """OpenAI-compatible API configuration (OpenAI / DeepSeek / etc.)."""

    api_key: SecretStr = Field(default=SecretStr(""), description="API key")
    base_url: str = Field(
        default="https://api.openai.com/v1",
        description="API base URL (use https://api.deepseek.com for DeepSeek)",
    )
    model: str = Field(default="gpt-4o-mini", description="Model to use for SQL generation")
    max_tokens: int = Field(default=2000, ge=100, le=8192, description="Maximum tokens in response")
    temperature: float = Field(
        default=0.0, ge=0.0, le=2.0, description="Temperature for response randomness"
    )
    timeout: float = Field(
        default=60.0, ge=5.0, le=180.0, description="API request timeout in seconds"
    )

    @field_validator("api_key")
    @classmethod
    def validate_api_key(cls, v: SecretStr) -> SecretStr:
        """Validate API key is not empty and has correct format."""
        api_key_str = v.get_secret_value()
        if not api_key_str or not api_key_str.strip():
            raise ValueError("OpenAI API key must not be empty")
        if not api_key_str.startswith("sk-"):
            raise ValueError("OpenAI API key must start with 'sk-'")
        return v


class SecurityConfig(BaseModel):
    """Security and access control configuration."""

    allow_write_operations: bool = Field(
        default=False, description="Allow write operations (INSERT, UPDATE, DELETE)"
    )
    blocked_functions: list[str] = Field(
        default_factory=lambda: [
            "pg_sleep",
            "pg_read_file",
            "pg_write_file",
            "lo_import",
            "lo_export",
        ],
        description="List of blocked PostgreSQL functions",
    )
    blocked_tables: list[str] = Field(
        default_factory=list,
        description="Tables that cannot be queried (case-insensitive)",
    )
    blocked_columns: list[str] = Field(
        default_factory=list,
        description="Columns that cannot be selected (format: table.column)",
    )
    allow_explain: bool = Field(
        default=False, description="Allow EXPLAIN statements in addition to SELECT"
    )
    max_rows: int = Field(default=10000, ge=1, le=100000, description="Maximum rows to return")
    max_execution_time: float = Field(
        default=30.0, ge=1.0, le=300.0, description="Maximum query execution time in seconds"
    )
    readonly_role: str | None = Field(
        default=None, description="PostgreSQL role to switch to for read-only access"
    )
    safe_search_path: str = Field(
        default="public", description="Safe search_path to set during query execution"
    )

    @field_validator("blocked_functions", "blocked_tables", "blocked_columns", mode="before")
    @classmethod
    def parse_comma_separated(cls, v: str | list[str]) -> list[str]:
        """Parse comma-separated string or list."""
        if isinstance(v, str):
            return [item.strip() for item in v.split(",") if item.strip()]
        return v


class ValidationConfig(BaseModel):
    """Query validation configuration."""

    max_question_length: int = Field(
        default=10000, ge=1, le=50000, description="Maximum question length in characters"
    )
    min_confidence_score: int = Field(
        default=70, ge=0, le=100, description="Minimum confidence score (0-100)"
    )
    enabled: bool = Field(default=True, description="Enable result validation using LLM")
    sample_rows: int = Field(
        default=5, ge=1, le=100, description="Number of sample rows to include in validation"
    )
    timeout_seconds: float = Field(
        default=10.0, ge=1.0, le=60.0, description="Result validation timeout in seconds"
    )


class CacheConfig(BaseModel):
    """Schema cache configuration."""

    schema_ttl: int = Field(
        default=3600, ge=60, le=86400, description="Schema cache TTL in seconds"
    )
    max_size: int = Field(default=100, ge=1, le=1000, description="Maximum cache entries")
    enabled: bool = Field(default=True, description="Enable schema caching")


class ResilienceConfig(BaseModel):
    """Resilience and fault tolerance configuration."""

    max_retries: int = Field(default=3, ge=0, le=10, description="Maximum retry attempts")
    retry_delay: float = Field(
        default=0.1, ge=0.0, le=10.0, description="Initial retry delay in seconds"
    )
    backoff_factor: float = Field(
        default=2.0, ge=1.0, le=10.0, description="Exponential backoff factor"
    )
    circuit_breaker_threshold: int = Field(
        default=5, ge=1, le=100, description="Failures before circuit opens"
    )
    circuit_breaker_timeout: float = Field(
        default=60.0, ge=10.0, le=300.0, description="Circuit breaker timeout in seconds"
    )
    max_concurrent_queries: int = Field(
        default=10, ge=1, le=100, description="Max concurrent DB queries"
    )
    max_concurrent_llm: int = Field(
        default=5, ge=1, le=100, description="Max concurrent LLM calls"
    )
    rate_limit_timeout: float = Field(
        default=30.0, ge=0.1, le=300.0, description="Timeout waiting for rate limiter slot"
    )


class ObservabilityConfig(BaseModel):
    """Observability and monitoring configuration."""

    metrics_enabled: bool = Field(default=True, description="Enable Prometheus metrics")
    metrics_port: int = Field(
        default=9090, ge=1024, le=65535, description="Metrics HTTP server port"
    )
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = Field(
        default="INFO", description="Logging level"
    )
    log_format: Literal["json", "text"] = Field(default="json", description="Log format")


def _as_bool(value: str | None, default: bool) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _database_from_env() -> dict[str, Any]:
    data: dict[str, Any] = {}
    if v := _env("DATABASE_HOST"):
        data["host"] = v
    if v := _env("DATABASE_PORT"):
        data["port"] = int(v)
    if v := _env("DATABASE_NAME"):
        data["name"] = v
    if v := _env("DATABASE_USER"):
        data["user"] = v
    if "DATABASE_PASSWORD" in os.environ:
        data["password"] = os.environ["DATABASE_PASSWORD"]
    if v := _env("DATABASE_MIN_POOL_SIZE"):
        data["min_pool_size"] = int(v)
    if v := _env("DATABASE_MAX_POOL_SIZE"):
        data["max_pool_size"] = int(v)
    if v := _env("DATABASE_POOL_TIMEOUT"):
        data["pool_timeout"] = float(v)
    if v := _env("DATABASE_COMMAND_TIMEOUT"):
        data["command_timeout"] = float(v)
    return data


def _openai_from_env() -> dict[str, Any]:
    data: dict[str, Any] = {}
    if key := _env("OPENAI_API_KEY"):
        data["api_key"] = key
    if base_url := _env("OPENAI_BASE_URL"):
        data["base_url"] = base_url
    if model := _env("OPENAI_MODEL"):
        data["model"] = model
    if max_tokens := _env("OPENAI_MAX_TOKENS"):
        data["max_tokens"] = int(max_tokens)
    if temperature := _env("OPENAI_TEMPERATURE"):
        data["temperature"] = float(temperature)
    if timeout := _env("OPENAI_TIMEOUT"):
        data["timeout"] = float(timeout)
    return data


def _security_from_env() -> dict[str, Any]:
    data: dict[str, Any] = {}
    if _env("SECURITY_ALLOW_WRITE_OPERATIONS") is not None:
        data["allow_write_operations"] = _as_bool(_env("SECURITY_ALLOW_WRITE_OPERATIONS"), False)
    if _env("SECURITY_ALLOW_EXPLAIN") is not None:
        data["allow_explain"] = _as_bool(_env("SECURITY_ALLOW_EXPLAIN"), False)
    if blocked := _env("SECURITY_BLOCKED_FUNCTIONS"):
        data["blocked_functions"] = blocked
    if tables := _env("SECURITY_BLOCKED_TABLES"):
        data["blocked_tables"] = tables
    if columns := _env("SECURITY_BLOCKED_COLUMNS"):
        data["blocked_columns"] = columns
    if max_rows := _env("SECURITY_MAX_ROWS"):
        data["max_rows"] = int(max_rows)
    if max_exec := _env("SECURITY_MAX_EXECUTION_TIME"):
        data["max_execution_time"] = float(max_exec)
    if role := _env("SECURITY_READONLY_ROLE"):
        data["readonly_role"] = role
    if search_path := _env("SECURITY_SAFE_SEARCH_PATH"):
        data["safe_search_path"] = search_path
    return data


def _validation_from_env() -> dict[str, Any]:
    data: dict[str, Any] = {}
    if v := _env("VALIDATION_MAX_QUESTION_LENGTH"):
        data["max_question_length"] = int(v)
    if v := _env("VALIDATION_MIN_CONFIDENCE_SCORE"):
        data["min_confidence_score"] = int(v)
    elif v := _env("VALIDATION_CONFIDENCE_THRESHOLD"):
        data["min_confidence_score"] = int(v)
    if v := _env("VALIDATION_ENABLED"):
        data["enabled"] = _as_bool(v, True)
    if v := _env("VALIDATION_SAMPLE_ROWS"):
        data["sample_rows"] = int(v)
    if v := _env("VALIDATION_TIMEOUT_SECONDS"):
        data["timeout_seconds"] = float(v)
    return data


def _cache_from_env() -> dict[str, Any]:
    data: dict[str, Any] = {}
    if v := _env("CACHE_ENABLED"):
        data["enabled"] = _as_bool(v, True)
    if v := _env("CACHE_SCHEMA_TTL"):
        data["schema_ttl"] = int(v)
    if v := _env("CACHE_MAX_SIZE"):
        data["max_size"] = int(v)
    return data


def _resilience_from_env() -> dict[str, Any]:
    data: dict[str, Any] = {}
    mapping = {
        "max_retries": ("RESILIENCE_MAX_RETRIES", int),
        "retry_delay": ("RESILIENCE_RETRY_DELAY", float),
        "backoff_factor": ("RESILIENCE_BACKOFF_FACTOR", float),
        "circuit_breaker_threshold": ("RESILIENCE_CIRCUIT_BREAKER_THRESHOLD", int),
        "circuit_breaker_timeout": ("RESILIENCE_CIRCUIT_BREAKER_TIMEOUT", float),
        "max_concurrent_queries": ("RESILIENCE_MAX_CONCURRENT_QUERIES", int),
        "max_concurrent_llm": ("RESILIENCE_MAX_CONCURRENT_LLM", int),
        "rate_limit_timeout": ("RESILIENCE_RATE_LIMIT_TIMEOUT", float),
    }
    for field, (env_key, caster) in mapping.items():
        if (v := _env(env_key)) is not None:
            data[field] = caster(v)
    return data


def _observability_from_env() -> dict[str, Any]:
    data: dict[str, Any] = {}
    if v := _env("OBSERVABILITY_METRICS_ENABLED"):
        data["metrics_enabled"] = _as_bool(v, True)
    if v := _env("OBSERVABILITY_METRICS_PORT"):
        data["metrics_port"] = int(v)
    if v := _env("OBSERVABILITY_LOG_LEVEL"):
        data["log_level"] = v
    if v := _env("OBSERVABILITY_LOG_FORMAT"):
        data["log_format"] = v
    return data


class Settings(BaseSettings):
    """Main application settings aggregating all config sections."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    environment: Literal["development", "staging", "production"] = Field(
        default="development", description="Application environment"
    )

    database: DatabaseConfig = Field(default_factory=DatabaseConfig)
    database_names: str = Field(
        default="",
        description="Comma-separated database names for multi-DB support",
    )
    openai: OpenAIConfig = Field(
        default_factory=lambda: OpenAIConfig(api_key=SecretStr("sk-unset"))
    )
    security: SecurityConfig = Field(default_factory=SecurityConfig)
    validation: ValidationConfig = Field(default_factory=ValidationConfig)
    cache: CacheConfig = Field(default_factory=CacheConfig)
    resilience: ResilienceConfig = Field(default_factory=ResilienceConfig)
    observability: ObservabilityConfig = Field(default_factory=ObservabilityConfig)

    @model_validator(mode="before")
    @classmethod
    def hydrate_from_env(cls, data: Any) -> Any:
        """Fill nested configs from DATABASE_*/SECURITY_* process env vars."""
        if not isinstance(data, dict):
            return data
        data = dict(data)

        def merge(section: str, env_data: dict[str, Any]) -> None:
            current = data.get(section)
            if isinstance(current, BaseModel):
                return
            base = dict(env_data)
            if isinstance(current, dict):
                base.update({k: v for k, v in current.items() if v is not None})
            if base:
                data[section] = base

        if "database" not in data or isinstance(data.get("database"), dict):
            merge("database", _database_from_env())
        if "openai" not in data or isinstance(data.get("openai"), dict):
            merge("openai", _openai_from_env())
        if "security" not in data or isinstance(data.get("security"), dict):
            merge("security", _security_from_env())
        if "validation" not in data or isinstance(data.get("validation"), dict):
            merge("validation", _validation_from_env())
        if "cache" not in data or isinstance(data.get("cache"), dict):
            merge("cache", _cache_from_env())
        if "resilience" not in data or isinstance(data.get("resilience"), dict):
            merge("resilience", _resilience_from_env())
        if "observability" not in data or isinstance(data.get("observability"), dict):
            merge("observability", _observability_from_env())

        if not data.get("database_names") and _env("DATABASE_NAMES"):
            data["database_names"] = _env("DATABASE_NAMES")
        if not data.get("environment") and _env("ENVIRONMENT"):
            data["environment"] = _env("ENVIRONMENT")
        return data

    @property
    def databases(self) -> list[DatabaseConfig]:
        """Resolve all configured databases (multi-DB aware)."""
        names = [n.strip() for n in self.database_names.split(",") if n.strip()]
        if not names:
            return [self.database]

        seen: set[str] = set()
        ordered: list[str] = []
        for name in names:
            if name not in seen:
                seen.add(name)
                ordered.append(name)
        return [self.database.copy_with_name(name) for name in ordered]

    @property
    def is_production(self) -> bool:
        """Check if running in production environment."""
        return self.environment == "production"

    @property
    def is_development(self) -> bool:
        """Check if running in development environment."""
        return self.environment == "development"


_settings: Settings | None = None


def get_settings() -> Settings:
    """Get or create global settings instance."""
    global _settings
    if _settings is None:
        load_dotenv()
        _settings = Settings()
    return _settings


def reset_settings() -> None:
    """Reset global settings instance. Useful for testing."""
    global _settings
    _settings = None
