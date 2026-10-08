# 作业说明（研发岗第 2 次作业）— 汤豪

本仓库面向 **安全运营 + 企业业务** 四库场景（`security_ops` / `saas_crm_large` / `ecommerce_medium` / `hospital_care`），默认库为 `security_ops`。

## 实现思路（与同学不同）

- **安全校验**：规则链架构 `security/rules.py`，`SQLValidator` 按序执行 `StatementTypeRule` → `BlockedTableRule` 等
- **数据源**：额外拦截 CRM 审计表 `audit_logs`
- **Web 演示**：OpsQuery 琥珀色安全运营台（上指令甲板 + 下 Tab 遥测），与企业蓝表单布局明显不同

## 核心改动

1. 四库连接池与按库路由
2. 规则链式 SQL 安全网关（可独立扩展 Rule）
3. 弹性与 Prometheus 指标
4. 单元测试全绿，覆盖率 ≥ 80%

## 本地运行

```bash
uv sync
uv run python scripts/load_fixtures.py
uv run pytest tests/unit tests/integration/test_homework_features.py -q
uv run python scripts/run_http_demo.py
```

## 截图（`screenshots/`）

| 文件 | 说明 |
|------|------|
| `02_security_ops_query_success.png` | 安全运营库告警查询 |
| `03_saas_crm_query_success.png` | CRM 组织统计 |
| `04_audit_logs_rejected.png` | audit_logs 审计表拦截 |
| `05_hospital_care_query_success.png` | 医院库患者统计 |

## 提交

- 仓库：https://gitee.com/working520/tanghao-mcp
- 建议截图：02 + 04
