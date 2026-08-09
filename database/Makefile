SHELL := /bin/bash
.PHONY: help up down init init-postgres init-mongo seed verify reset psql mongosh schema-doc

help:
	@echo "make up              start postgres + mongo (docker compose)"
	@echo "make init            apply migrations + mongo schemas to empty databases"
	@echo "make seed            load sample data into both stores"
	@echo "make verify          run the invariant + dependency-guard suite"
	@echo "make reset           destroy volumes and rebuild from scratch"
	@echo "make schema-doc      regenerate docs/05-schema-reference.md from the live DB"
	@echo "make down            stop containers"

up:
	docker compose up -d
	@echo "waiting for health..."
	@until [ "$$(docker inspect -f '{{.State.Health.Status}}' codementor-postgres 2>/dev/null)" = "healthy" ]; do sleep 1; done
	@until [ "$$(docker inspect -f '{{.State.Health.Status}}' codementor-mongo 2>/dev/null)" = "healthy" ]; do sleep 1; done
	@echo "both databases healthy."

down:
	docker compose down

init: init-postgres init-mongo

init-postgres:
	@bash scripts/init-postgres.sh

init-mongo:
	@bash scripts/init-mongo.sh

seed:
	@bash scripts/init-postgres.sh --seed-only
	@bash scripts/init-mongo.sh --seed

verify:
	@set -a; [ -f .env ] && . ./.env; set +a; \
	 PGPASSWORD=$${POSTGRES_PASSWORD:-codementor} psql -v ON_ERROR_STOP=1 \
	   -h $${POSTGRES_HOST:-localhost} -p $${POSTGRES_PORT:-55432} \
	   -U $${POSTGRES_USER:-codementor} -d $${POSTGRES_DB:-codementor} \
	   -f postgres/verify.sql

reset:
	docker compose down -v
	$(MAKE) up
	$(MAKE) init
	$(MAKE) seed
	$(MAKE) verify

psql:
	@set -a; [ -f .env ] && . ./.env; set +a; \
	 PGPASSWORD=$${POSTGRES_PASSWORD:-codementor} psql \
	   -h $${POSTGRES_HOST:-localhost} -p $${POSTGRES_PORT:-55432} \
	   -U $${POSTGRES_USER:-codementor} -d $${POSTGRES_DB:-codementor}

mongosh:
	@set -a; [ -f .env ] && . ./.env; set +a; \
	 mongosh "mongodb://$${MONGO_USER:-codementor}:$${MONGO_PASSWORD:-codementor}@$${MONGO_HOST:-localhost}:$${MONGO_PORT:-57017}/$${MONGO_DB:-codementor}?authSource=admin"

schema-doc:
	@bash scripts/dump-catalog.sh .catalog
	@node scripts/gen-schema-doc.js .catalog > docs/05-schema-reference.md
	@echo "docs/05-schema-reference.md regenerated from the live schema."
