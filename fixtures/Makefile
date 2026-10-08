# ============================================================================
# PostgreSQL MCP - Demo Databases (single init script)
# ============================================================================

PGHOST ?= localhost
PGPORT ?= 5432
PGUSER ?= root
PGPASSWORD ?= 123456
PSQL = psql -h $(PGHOST) -p $(PGPORT) -U $(PGUSER)
INIT_SQL = init_all.sql

DBS = blog_small ecommerce_medium saas_crm_large hr_system hospital_care security_ops

.PHONY: all help create-all drop-all rebuild-all info list check-connection

all: create-all

help:
	@echo "PostgreSQL MCP demo databases (single script: $(INIT_SQL))"
	@echo ""
	@echo "  make create-all   - Create all 6 databases"
	@echo "  make drop-all     - Drop all 6 databases"
	@echo "  make rebuild-all  - Drop and recreate"
	@echo "  make info         - Show database list"
	@echo "  make list         - List existing demo DBs on server"
	@echo ""
	@echo "Environment: PGHOST PGPORT PGUSER PGPASSWORD"

create-all:
	@echo "Creating all demo databases from $(INIT_SQL)..."
	@$(PSQL) -f $(INIT_SQL)
	@echo "Done."

drop-all:
	@for db in $(DBS); do \
		echo "Dropping $$db..."; \
		$(PSQL) -c "DROP DATABASE IF EXISTS $$db;" || true; \
	done

rebuild-all: drop-all create-all

info:
	@echo "Init script: $(INIT_SQL)"
	@echo "Databases: $(DBS)"

list:
	@$(PSQL) -t -c "SELECT datname FROM pg_database WHERE datname IN ('blog_small','ecommerce_medium','saas_crm_large','hr_system','hospital_care','security_ops') ORDER BY datname;"

check-connection:
	@$(PSQL) -c "SELECT version();"
