#!/usr/bin/env bash
# Creates collections, applies $jsonSchema validators and builds indexes.
#
# Uses `mongosh` from the host when available; otherwise falls back to the mongosh that ships
# inside the running container, so nothing extra has to be installed to bring the stack up.
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

HOST="${MONGO_HOST:-localhost}"
PORT="${MONGO_PORT:-57017}"
USER="${MONGO_USER:-codementor}"
PASS="${MONGO_PASSWORD:-codementor}"
DB="${MONGO_DB:-codementor}"
CONTAINER="${MONGO_CONTAINER:-codementor-mongo}"

FILES=("mongo/init.js")
[ "${1:-}" = "--seed" ] && FILES+=("mongo/seed/seed.js")

if command -v mongosh >/dev/null 2>&1; then
  URI="mongodb://${USER}:${PASS}@${HOST}:${PORT}/${DB}?authSource=admin"
  for f in "${FILES[@]}"; do
    MONGO_DB="$DB" mongosh "$URI" --quiet --file "$f"
  done
  exit 0
fi

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "error: mongosh is not installed and container '$CONTAINER' is not running." >&2
  echo "       start it with 'docker compose up -d', or install mongosh." >&2
  exit 1
fi

echo "mongosh not found on PATH — using the copy inside '$CONTAINER'."

# MSYS_NO_PATHCONV stops Git Bash on Windows rewriting container paths into C:\... .
export MSYS_NO_PATHCONV=1

# Connect over the container's own loopback, so the published host port is irrelevant.
URI="mongodb://${USER}:${PASS}@localhost:27017/${DB}?authSource=admin"

docker exec "$CONTAINER" rm -rf /tmp/mongo
docker cp mongo "$CONTAINER":/tmp/mongo >/dev/null

for f in "${FILES[@]}"; do
  docker exec -w /tmp -e MONGO_DB="$DB" "$CONTAINER" mongosh "$URI" --quiet --file "$f"
done
