"""汤豪 · SQL 安全规则链：每条规则独立校验，按序执行。"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

import sqlglot
from sqlglot import exp

from pg_mcp.config.settings import SecurityConfig
from pg_mcp.models.errors import SecurityViolationError, SQLParseError


@dataclass(slots=True)
class ValidationContext:
    """规则链共享的解析上下文。"""

    raw_sql: str
    statement: exp.Expression
    config: SecurityConfig
    blocked_tables: set[str] = field(default_factory=set)
    blocked_columns: set[str] = field(default_factory=set)
    blocked_functions: set[str] = field(default_factory=set)
    allow_explain: bool = False

    # 与 SQLValidator 保持一致的类型集合
    ALLOWED_STATEMENT_TYPES: tuple[type, ...] = (
        exp.Select,
        exp.Union,
        exp.Intersect,
        exp.Except,
    )
    WRITE_STATEMENT_TYPES: tuple[type, ...] = (exp.Insert, exp.Update, exp.Delete)
    FORBIDDEN_STATEMENT_TYPES: tuple[type, ...] = (
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
    )

    def forbidden_types(self) -> set[type]:
        forbidden = set(self.FORBIDDEN_STATEMENT_TYPES)
        if self.config.allow_write_operations:
            forbidden -= set(self.WRITE_STATEMENT_TYPES)
        return forbidden

    def allowed_types(self) -> set[type]:
        allowed = set(self.ALLOWED_STATEMENT_TYPES)
        if self.config.allow_write_operations:
            allowed |= set(self.WRITE_STATEMENT_TYPES)
        return allowed


class SecurityRule(Protocol):
    """单条安全规则接口。"""

    def check(self, ctx: ValidationContext, root: exp.Expression) -> str | None:
        """返回错误信息；通过则返回 None。"""
        ...


def parse_context(
    sql: str,
    config: SecurityConfig,
    blocked_tables: set[str],
    blocked_columns: set[str],
    blocked_functions: set[str],
    allow_explain: bool,
) -> ValidationContext:
    """解析 SQL 并构造规则链上下文。"""
    if not sql or not sql.strip():
        raise SQLParseError("SQL query cannot be empty")

    try:
        parsed = sqlglot.parse(sql, read="postgres")
    except Exception as e:
        raise SQLParseError(f"Failed to parse SQL: {e}") from e

    if len(parsed) > 1:
        raise SecurityViolationError(
            "Multiple statements not allowed. Only single SELECT queries are permitted."
        )
    if not parsed or parsed[0] is None:
        raise SQLParseError("No valid SQL statement found")

    statement = parsed[0]
    if isinstance(statement, exp.Command):
        cmd_name = str(statement.this).upper() if statement.this else ""
        if cmd_name == "EXPLAIN":
            if not allow_explain:
                raise SecurityViolationError("EXPLAIN statements are not allowed")
            return ValidationContext(
                raw_sql=sql,
                statement=statement,
                config=config,
                blocked_tables=blocked_tables,
                blocked_columns=blocked_columns,
                blocked_functions=blocked_functions,
                allow_explain=allow_explain,
            )
        raise SecurityViolationError(
            f"Command '{cmd_name}' is not allowed. Only SELECT queries are permitted."
        )

    return ValidationContext(
        raw_sql=sql,
        statement=statement,
        config=config,
        blocked_tables=blocked_tables,
        blocked_columns=blocked_columns,
        blocked_functions=blocked_functions,
        allow_explain=allow_explain,
    )


def _main_query(statement: exp.Expression) -> exp.Expression:
    if isinstance(statement, exp.With):
        if not statement.this:
            raise SQLParseError("WITH statement has no main query")
        return statement.this
    return statement


class StatementTypeRule:
    """校验顶层语句类型。"""

    def check(self, ctx: ValidationContext, root: exp.Expression) -> str | None:
        if isinstance(root, exp.Command) and str(root.this).upper() == "EXPLAIN":
            return None
        main = _main_query(root)
        for forbidden in ctx.forbidden_types():
            if isinstance(main, forbidden):
                name = forbidden.__name__.upper()
                if forbidden in ctx.WRITE_STATEMENT_TYPES:
                    return (
                        f"{name} statements are not allowed. "
                        "Write operations are disabled (set SECURITY_ALLOW_WRITE_OPERATIONS=true to enable)."
                    )
                return f"{name} statements are not allowed. Only SELECT queries are permitted."
        if not isinstance(main, tuple(ctx.allowed_types())):
            return (
                f"Statement type {type(main).__name__} is not allowed. "
                "Only SELECT queries are permitted."
            )
        return None


class DangerousFunctionRule:
    """拦截危险函数调用。"""

    def check(self, ctx: ValidationContext, root: exp.Expression) -> str | None:
        for func in root.find_all(exp.Func):
            name = (func.name or "").lower()
            if name in ctx.blocked_functions:
                return f"Function '{name}' is blocked for security reasons"
        return None


class BlockedTableRule:
    """拦截敏感表访问。"""

    def check(self, ctx: ValidationContext, root: exp.Expression) -> str | None:
        if not ctx.blocked_tables:
            return None
        for table in root.find_all(exp.Table):
            name = (table.name or "").lower()
            if name in ctx.blocked_tables:
                return f"Access to table '{name}' is not allowed"
        return None


class BlockedColumnRule:
    """拦截敏感列访问。"""

    def check(self, ctx: ValidationContext, root: exp.Expression) -> str | None:
        if not ctx.blocked_columns:
            return None
        for column in root.find_all(exp.Column):
            column_name = (column.name or "").lower()
            if not column_name:
                continue
            if column_name in ctx.blocked_columns:
                return f"Access to column '{column_name}' is not allowed"
            if column.table:
                qualified = f"{column.table.lower()}.{column_name}"
                if qualified in ctx.blocked_columns:
                    return f"Access to column '{qualified}' is not allowed"
            for blocked in ctx.blocked_columns:
                if "." in blocked and blocked.rsplit(".", 1)[-1] == column_name:
                    return f"Access to column '{blocked}' is not allowed"
        return None


class SubquerySafetyRule:
    """子查询仅允许 SELECT。"""

    def check(self, ctx: ValidationContext, root: exp.Expression) -> str | None:
        for subquery in root.find_all(exp.Subquery):
            if not subquery.this:
                continue
            inner = subquery.this
            for forbidden in ctx.forbidden_types():
                if isinstance(inner, forbidden):
                    return f"{forbidden.__name__.upper()} statements in subqueries are not allowed"
            allowed_inner = (exp.Select, exp.With)
            if ctx.config.allow_write_operations:
                allowed_inner = (*allowed_inner, *ctx.WRITE_STATEMENT_TYPES)
            if not isinstance(inner, allowed_inner):
                return "Subqueries must contain only SELECT statements"
        return None


def build_rule_chain() -> list[SecurityRule]:
    """构造默认规则链（顺序即执行顺序）。"""
    return [
        StatementTypeRule(),
        DangerousFunctionRule(),
        BlockedTableRule(),
        BlockedColumnRule(),
        SubquerySafetyRule(),
    ]
