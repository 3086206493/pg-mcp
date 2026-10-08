"""汤豪 · 作业演示脚本（无需 LLM 即可展示多库与安全控制）。

Usage:
  python scripts/demo_homework.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from pg_mcp.config.settings import DatabaseConfig, OpenAIConfig, SecurityConfig, Settings
from pg_mcp.models.errors import SecurityViolationError
from pg_mcp.services.sql_validator import SQLValidator


def banner(title: str) -> None:
    print("\n" + "─" * 56)
    print(f"  {title}")
    print("─" * 56)


def demo_multi_database() -> None:
    banner("[汤豪] 多库路由配置")
    settings = Settings(
        openai=OpenAIConfig(api_key="sk-demo-key-for-local-script"),
        database=DatabaseConfig(host="localhost", user="root", password="123456", name="security_ops"),
        database_names="security_ops,saas_crm_large,ecommerce_medium,hospital_care",
        security=SecurityConfig(
            blocked_tables=["user_sessions", "api_keys", "audit_logs"],
            blocked_columns=["users.password_hash"],
            allow_explain=False,
        ),
        _env_file=None,
    )
    print("已注册数据源：")
    for db in settings.databases:
        print(f"  ▸ {db.name}  ({db.host}:{db.port})")
    print(f"\n表级黑名单: {settings.security.blocked_tables}")
    print(f"列级黑名单: {settings.security.blocked_columns}")


def demo_security() -> None:
    banner("[汤豪] 规则链 SQL 安全校验")
    validator = SQLValidator(
        config=SecurityConfig(allow_write_operations=False),
        blocked_tables=["user_sessions", "api_keys", "audit_logs"],
        blocked_columns=["users.password_hash"],
        allow_explain=False,
    )
    cases = [
        ("正常 SELECT", "SELECT id, email FROM users LIMIT 10"),
        ("敏感表 sessions", "SELECT * FROM user_sessions"),
        ("审计日志表", "SELECT * FROM audit_logs"),
        ("敏感列", "SELECT password_hash FROM users"),
        ("EXPLAIN", "EXPLAIN SELECT * FROM users"),
        ("DELETE", "DELETE FROM users"),
    ]
    results = []
    for name, sql in cases:
        try:
            validator.validate_or_raise(sql)
            status, detail = "PASS", None
        except SecurityViolationError as e:
            status, detail = "BLOCK", {"code": e.code.value, "message": e.message}
        print(f"  [{status:5}] {name:16}  {sql[:42]}")
        if detail:
            print(f"          └─ {detail['message']}")
        results.append({"case": name, "sql": sql, "status": status, "detail": detail})

    out = ROOT / "fixtures" / "DEMO_SECURITY_RESULT.json"
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n结果已保存: {out}")


def main() -> None:
    print("=" * 56)
    print("  OpsQuery · pg-mcp 作业演示  |  作者：汤豪")
    print("=" * 56)
    demo_multi_database()
    demo_security()
    print("\n演示结束，可截图上方输出用于作业提交。\n")


if __name__ == "__main__":
    main()
