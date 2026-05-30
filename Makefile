# PostgreSQL Isolation Levels Lab
#
# Run `make help` to see available targets.

WEBSITE_DIR := website

.DEFAULT_GOAL := help

.PHONY: help up down restart psql setup reset logs ps clean \
        site-install site-dev site-build site-preview

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ----------------------------------------------------------------------
# Database environment
# ----------------------------------------------------------------------

up: ## Start PostgreSQL in Docker (creates .env if missing)
	@test -f .env || cp .env.example .env
	docker compose up -d

down: ## Stop and remove the container and its volume (destroys data)
	docker compose down -v

restart: down up ## Recreate the database from scratch

ps: ## Show container status
	docker compose ps

logs: ## Follow PostgreSQL logs (statements arrive here)
	docker compose logs -f postgres

psql: ## Open an interactive psql session (run in two terminals for demos)
	./scripts/psql.sh

setup: ## Load schema + seed data into the running database (run once)
	docker compose exec -T postgres \
	  psql -U "$${POSTGRES_USER:-lab}" -d "$${POSTGRES_DB:-isolation_lab}" -f /sql/00_setup.sql

reset: ## Reset all demo tables back to their seeded baseline
	./scripts/reset.sh

# ----------------------------------------------------------------------
# Reference website (Nextra)
# ----------------------------------------------------------------------

site-install: ## Install website dependencies
	cd $(WEBSITE_DIR) && npm install

site-dev: ## Run the website dev server (http://localhost:3000)
	cd $(WEBSITE_DIR) && npm run dev

site-build: ## Build the static website + Pagefind search index
	cd $(WEBSITE_DIR) && npm run build

site-preview: ## Serve the built website locally
	cd $(WEBSITE_DIR) && npm run preview

clean: ## Remove website build artifacts and dependencies
	rm -rf $(WEBSITE_DIR)/.next $(WEBSITE_DIR)/out $(WEBSITE_DIR)/node_modules
