"""汤豪 · 规则链式 SQL 安全校验器（SQLGlot 解析 + 可组合规则）。

与程文旭的单类内联校验不同，本实现将各检查项拆为独立 Rule，按链式顺序执行。
"""

from typing import ClassVar

import sqlglot
from sqlglot import exp

from pg_mcp.config.settings import SecurityConfig
from pg_mcp.models.errors import SecurityViolationError, SQLParseError
from pg_mcp.security.rules import build_rule_chain, parse_context


class SQLValidator:
    """规则链 SQL 安全校验器。"""

    ALLOWED_STATEMENT_TYPES: ClassVar = {exp.Select, exp.Union, exp.Intersect, exp.Except}
    ALLOWED_TOP_LEVEL: ClassVar = {
        exp.Select,
        exp.Union,
        exp.Intersect,
        exp.Except,
        exp.With,
        exp.Subquery,
    }
    WRITE_STATEMENT_TYPES: ClassVar = {exp.Insert, exp.Update, exp.Delete}
    FORBIDDEN_STATEMENT_TYPES: ClassVar = {
        exp.Insert,
        exp.Update,
        exp.Delete,
        exp.Drop,
        exp.Create,
        exp.Alter,
        exp.Grant,
        exp.Revoke,
        exp.Set,
        exp.Command,
        exp.Use,
        exp.Merge,
    }
    BUILTIN_DANGEROUS_FUNCTIONS: ClassVar = {
        "pg_sleep",
        "pg_terminate_backend",
        "pg_cancel_backend",
        "pg_reload_conf",
        "pg_rotate_logfile",
        "pg_read_file",
        "pg_read_binary_file",
        "pg_ls_dir",
        "pg_stat_file",
        "lo_import",
        "lo_export",
        "dblink",
        "dblink_exec",
        "dblink_connect",
        "dblink_open",
        "pg_write_file",
        "pg_execute_sql",
        "copy_from",
        "copy_to",
    }

    def __init__(
        self,
        config: SecurityConfig,
        blocked_tables: list[str] | None = None,
        blocked_columns: list[str] | None = None,
        allow_explain: bool = False,
    ) -> None:
        self.config = config
        self.blocked_tables = {t.lower() for t in (blocked_tables or [])}
        self.blocked_columns = {c.lower() for c in (blocked_columns or [])}
        self.allow_explain = allow_explain
        self.blocked_functions = self.BUILTIN_DANGEROUS_FUNCTIONS | {
            f.lower() for f in config.blocked_functions
        }
        self._rules = build_rule_chain()

    def validate(self, sql: str) -> tuple[bool, str | None]:
        try:
            self.validate_or_raise(sql)
            return (True, None)
        except (SecurityViolationError, SQLParseError) as e:
            return (False, str(e))

    def validate_or_raise(self, sql: str) -> None:
        ctx = parse_context(
            sql,
            self.config,
            self.blocked_tables,
            self.blocked_columns,
            self.blocked_functions,
            self.allow_explain,
        )
        if isinstance(ctx.statement, exp.Command) and str(ctx.statement.this).upper() == "EXPLAIN":
            return
        for rule in self._rules:
            if error := rule.check(ctx, ctx.statement):
                raise SecurityViolationError(error)

    def normalize_sql(self, sql: str) -> str:
        try:
            parsed = sqlglot.parse_one(sql, read="postgres")
            return parsed.sql(dialect="postgres", pretty=False)
        except Exception as e:
            raise SQLParseError(f"Failed to normalize SQL: {e}") from e

    def extract_tables(self, sql: str) -> list[str]:
        try:
            parsed = sqlglot.parse_one(sql, read="postgres")
            tables = []
            for table in parsed.find_all(exp.Table):
                if table.name:
                    tables.append(table.name.lower())
            return sorted(set(tables))
        except Exception as e:
            raise SQLParseError(f"Failed to extract tables: {e}") from e
