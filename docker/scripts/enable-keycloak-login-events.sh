#!/usr/bin/env bash
# Turn on login events and let core-service read them.
#
# The same two settings exist in configure-codementor-realm.sh, which is the source of
# truth for a realm built from scratch. This script is the narrow version for a realm that
# is already provisioned and running: the full script also calls upsert_env, which rotates
# client secrets into docker/.env, and every local .env holding the old value would stop
# working. Applying one change should not cost a credential rotation.
#
# Idempotent — running it twice changes nothing the second time.
#
#   ./enable-keycloak-login-events.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root/docker"

set -a
. ./.env
set +a

container=codementor-keycloak
kcadm=/opt/keycloak/bin/kcadm.sh
config_file=/tmp/codementor-events-kcadm.config
realm=codementor

cleanup() {
  docker exec "$container" rm -f "$config_file" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kc() {
  docker exec "$container" "$kcadm" "$@" --config "$config_file"
}

docker exec "$container" "$kcadm" config credentials \
  --config "$config_file" \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

# Only the event types the admin console shows. Keycloak records dozens if asked, and each
# one is a row it stores and expires for nobody's benefit.
#
# 30 days, not forever: these answer "what happened to this account lately". Long-term
# traceability of administrative action is what the audit_logs table is for, and that one
# is append-only.
kc update "realms/$realm" \
  -s eventsEnabled=true \
  -s eventsExpiration=2592000 \
  -s 'enabledEventTypes=["LOGIN","LOGIN_ERROR","LOGOUT","REGISTER","REGISTER_ERROR","UPDATE_PASSWORD"]' \
  -s adminEventsEnabled=false >/dev/null
echo "realm $realm: login events enabled, 30 day retention"

# Read-only, and separate from the user-management roles the account already holds, so it
# does not widen what this service account can change.
kc add-roles -r "$realm" \
  --uusername service-account-codementor-user-service \
  --cclientid realm-management \
  --rolename view-events >/dev/null 2>&1 || true
echo "service-account-codementor-user-service: view-events granted"

kc get "realms/$realm" --fields eventsEnabled,eventsExpiration,enabledEventTypes
