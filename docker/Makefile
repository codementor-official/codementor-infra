SHELL := /bin/bash
.PHONY: help ec2-up ec2-down ec2-status migrate init-mongo configure-keycloak verify

COMPOSE := docker compose -f docker-compose.dev.yml

help:
	@echo "make ec2-up      start the EC2 development stack"
	@echo "make ec2-down    stop containers without deleting data"
	@echo "make ec2-status  show service state"
	@echo "make migrate     apply unapplied PostgreSQL migrations"
	@echo "make init-mongo  apply MongoDB validators and indexes"
	@echo "make configure-keycloak  allow HTTP for the development realm"
	@echo "make verify      verify PostgreSQL, MongoDB, and Keycloak"

ec2-up:
	$(COMPOSE) up -d

ec2-down:
	$(COMPOSE) down

ec2-status:
	$(COMPOSE) ps

migrate:
	bash scripts/migrate-postgres.sh

init-mongo:
	bash scripts/init-mongo.sh

configure-keycloak:
	bash scripts/configure-keycloak-dev.sh

verify:
	bash scripts/verify-stack.sh
