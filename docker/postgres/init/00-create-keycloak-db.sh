#!/usr/bin/env bash
set -euo pipefail

: "${KEYCLOAK_DB_USER:?KEYCLOAK_DB_USER is required}"
: "${KEYCLOAK_DB_PASSWORD:?KEYCLOAK_DB_PASSWORD is required}"
: "${KEYCLOAK_DB_NAME:?KEYCLOAK_DB_NAME is required}"

psql --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=keycloak_user="$KEYCLOAK_DB_USER" \
  --set=keycloak_password="$KEYCLOAK_DB_PASSWORD" \
  --set=keycloak_db="$KEYCLOAK_DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'keycloak_user', :'keycloak_password')
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = :'keycloak_user')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'keycloak_db', :'keycloak_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'keycloak_db')
\gexec
SQL
