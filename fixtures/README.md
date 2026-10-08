# PostgreSQL MCP 演示数据库

本目录提供 **单一初始化脚本** `init_all.sql`，一次性创建 pg-mcp 所需的 6 个演示库。

## 数据库一览

| 数据库 | 规模 | 说明 |
|--------|------|------|
| `blog_small` | 小 | 博客系统（用户、文章、评论、标签） |
| `ecommerce_medium` | 中 | 电商平台（商品、订单、支付、评价） |
| `saas_crm_large` | 大 | 企业 SaaS CRM（多租户、销售、工单） |
| `hr_system` | 中 | 人力资源（部门、员工、请假、薪资） |
| `hospital_care` | 中 | 医院业务（患者、预约、账单） |
| `security_ops` | 中 | 安全运营（告警、事件、漏洞、资产） |

## 快速初始化

### 方式 A：Python（推荐，支持远程库）

```bash
# 项目根目录
uv run python scripts/load_fixtures.py
```

脚本会读取 `.env` 中的 `DATABASE_HOST` / `DATABASE_USER` / `DATABASE_PASSWORD`，
或默认连接 `159.75.33.167`。

### 方式 B：psql

```bash
cd fixtures
# Windows PowerShell:
$env:PGPASSWORD="123456"
psql -h 159.75.33.167 -U root -f init_all.sql
```

### 方式 C：Makefile

```bash
cd fixtures
make create-all    # 等价于 psql -f init_all.sql
make drop-all      # 删除 6 个库
make rebuild-all   # 重建
make list          # 查看已存在的演示库
```

## 与 pg-mcp 配置对应

`.env` 中需配置：

```bash
DATABASE_NAMES=blog_small,ecommerce_medium,saas_crm_large,hr_system,hospital_care,security_ops
```

## 文件说明

| 文件 | 用途 |
|------|------|
| `init_all.sql` | **唯一**建库脚本（6 库合一） |
| `Makefile` | 本地 psql 快捷命令 |
| `TEST_QUERIES.md` | 各库示例自然语言问题 |
| `DEMO_SECURITY_RESULT.json` | 安全演示预期输出 |

## 注意事项

- `init_all.sql` 内含 `DROP DATABASE`，会**清空并重建**上述 6 个库，请勿在生产环境执行。
- 脚本使用 psql 元命令 `\c` 切换数据库；`load_fixtures.py` 会按 `-- DATABASE:` 分段解析后逐库加载。
