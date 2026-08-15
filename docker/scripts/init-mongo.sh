#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root/docker"

set -a
. ./.env
set +a

export MONGO_CONTAINER=codementor-mongo
export MONGO_HOST=localhost
export MONGO_PORT="${MONGO_PORT:-27017}"

cd "$repo_root/database"
bash scripts/init-mongo.sh
