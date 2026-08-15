#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root/docker"

set -a
. ./.env
set +a

container=codementor-postgres
migration_dir=/tmp/codementor-migrations

docker exec "$container" rm -rf "$migration_dir"
docker cp "$repo_root/database/postgres/migrations" "$container:$migration_dir" >/dev/null

docker exec "$container" psql -v ON_ERROR_STOP=1 -q \
  -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  'CREATE TABLE IF NOT EXISTS infra_schema_migrations (filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());'

for migration in "$repo_root"/database/postgres/migrations/*.sql; do
  filename="$(basename "$migration")"
  applied="$(docker exec "$container" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc \
    "SELECT 1 FROM infra_schema_migrations WHERE filename = '$filename'")"

  if [ "$applied" = "1" ]; then
    printf '  %-44s already applied\n' "$filename"
    continue
  fi

  printf '  %-44s' "$filename"
  docker exec "$container" psql -v ON_ERROR_STOP=1 -q \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$migration_dir/$filename"
  docker exec "$container" psql -v ON_ERROR_STOP=1 -q \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
    "INSERT INTO infra_schema_migrations(filename) VALUES ('$filename')"
  echo ok
done
