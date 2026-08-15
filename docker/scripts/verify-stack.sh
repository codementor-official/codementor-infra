#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root/docker"

set -a
. ./.env
set +a

docker compose -f docker-compose.dev.yml ps
docker exec codementor-postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
docker exec codementor-mongo mongosh --quiet \
  "mongodb://${MONGO_USER}:${MONGO_PASSWORD}@localhost:27017/${MONGO_DB}?authSource=admin" \
  --eval 'quit(db.adminCommand({ ping: 1 }).ok ? 0 : 1)'
curl --fail --silent --show-error "http://127.0.0.1:${KEYCLOAK_HTTP_PORT:-8080}/realms/master/.well-known/openid-configuration" >/dev/null
echo "CodeMentor development infrastructure is healthy."
