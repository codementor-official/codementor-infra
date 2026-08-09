#!/usr/bin/env bash
# Applies every migration in order to an empty database. Idempotent only in the sense that
# it is safe to run against a fresh database; re-running against a populated one will fail
# on duplicate objects, which is intentional (use `make reset` instead).
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

HOST="${POSTGRES_HOST:-localhost}"
PORT="${POSTGRES_PORT:-55432}"
USER="${POSTGRES_USER:-codementor}"
DB="${POSTGRES_DB:-codementor}"
export PGPASSWORD="${POSTGRES_PASSWORD:-codementor}"

# ON_ERROR_STOP makes psql exit non-zero on the first failure instead of ploughing on.
PSQL=(psql -v ON_ERROR_STOP=1 -q -h "$HOST" -p "$PORT" -U "$USER" -d "$DB")

MODE="${1:-migrate}"   # migrate | --seed (migrate then seed) | --seed-only

if [ "$MODE" != "--seed-only" ]; then
  echo "== postgres migrations → ${USER}@${HOST}:${PORT}/${DB} =="
  for f in postgres/migrations/*.sql; do
    printf '  %-44s' "$(basename "$f")"
    "${PSQL[@]}" -f "$f"
    echo "ok"
  done
fi

if [ "$MODE" = "--seed" ] || [ "$MODE" = "--seed-only" ]; then
  echo "== seed =="
  for f in postgres/seed/*.sql; do
    printf '  %-44s' "$(basename "$f")"
    "${PSQL[@]}" -f "$f"
    echo "ok"
  done
fi

echo "done."
