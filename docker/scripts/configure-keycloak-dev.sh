#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root/docker"

set -a
. ./.env
set +a

container=codementor-keycloak
kcadm=/opt/keycloak/bin/kcadm.sh
config_file=/tmp/codementor-kcadm.config

cleanup() {
  docker exec "$container" rm -f "$config_file"
}
trap cleanup EXIT

docker exec "$container" "$kcadm" config credentials \
  --config "$config_file" \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

docker exec "$container" "$kcadm" update realms/master \
  --config "$config_file" \
  -s sslRequired=NONE >/dev/null

echo "Keycloak master realm allows HTTP for development."
