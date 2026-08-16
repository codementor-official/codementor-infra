#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root/docker"

set -a
. ./.env
set +a

container=codementor-keycloak
kcadm=/opt/keycloak/bin/kcadm.sh
config_file=/tmp/codementor-realm-kcadm.config
realm=codementor

cleanup() {
  docker exec "$container" rm -f "$config_file"
}
trap cleanup EXIT

kc() {
  docker exec "$container" "$kcadm" "$@" --config "$config_file"
}

upsert_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >>.env
  fi
}

generated_secret() {
  printf '%s%s' "$(tr -d '-' </proc/sys/kernel/random/uuid)" "$(tr -d '-' </proc/sys/kernel/random/uuid)"
}

ensure_secret_env() {
  local key="$1"
  local current="${!key:-}"
  if [ -z "$current" ]; then
    current="$(generated_secret)"
    upsert_env "$key" "$current"
    export "$key=$current"
  fi
}

client_id() {
  kc get clients -r "$realm" -q "clientId=$1" --fields id --format csv --noquotes 2>/dev/null | tail -n 1
}

ensure_realm_role() {
  local role="$1"
  local description="$2"
  if ! kc get "roles/$role" -r "$realm" >/dev/null 2>&1; then
    kc create roles -r "$realm" -s "name=$role" -s "description=$description" >/dev/null
  fi
}

ensure_public_client() {
  local client="$1"
  local name="$2"
  local redirects="$3"
  local origins="$4"
  local login_theme="$5"
  local id
  local logout_redirects
  local attributes
  logout_redirects="$(printf '%s' "$redirects" | sed 's/^\[//;s/\]$//;s/"//g;s/,/##/g')"
  attributes="{\"pkce.code.challenge.method\":\"S256\",\"post.logout.redirect.uris\":\"$logout_redirects\",\"login_theme\":\"$login_theme\"}"
  id="$(client_id "$client")"
  if [ -z "$id" ]; then
    id="$(kc create clients -r "$realm" -s "clientId=$client" -s "name=$name" -s enabled=true -s publicClient=true -s standardFlowEnabled=true -s directAccessGrantsEnabled=false -s "attributes=$attributes" -s "redirectUris=$redirects" -s "webOrigins=$origins" -i)"
  else
    kc update "clients/$id" -r "$realm" -s "name=$name" -s enabled=true -s publicClient=true -s standardFlowEnabled=true -s directAccessGrantsEnabled=false -s "attributes=$attributes" -s "redirectUris=$redirects" -s "webOrigins=$origins" >/dev/null
  fi
  printf '%s' "$id"
}

ensure_bearer_client() {
  local id
  id="$(client_id codementor-api)"
  if [ -z "$id" ]; then
    kc create clients -r "$realm" -s clientId=codementor-api -s 'name=CodeMentor API' -s enabled=true -s bearerOnly=true -s publicClient=false -i
  else
    kc update "clients/$id" -r "$realm" -s 'name=CodeMentor API' -s enabled=true -s bearerOnly=true -s publicClient=false >/dev/null
    printf '%s' "$id"
  fi
}

ensure_service_client() {
  local client="$1"
  local name="$2"
  local id
  id="$(client_id "$client")"
  if [ -z "$id" ]; then
    id="$(kc create clients -r "$realm" -s "clientId=$client" -s "name=$name" -s enabled=true -s publicClient=false -s clientAuthenticatorType=client-secret -s serviceAccountsEnabled=true -s standardFlowEnabled=false -s directAccessGrantsEnabled=false -i)"
  else
    kc update "clients/$id" -r "$realm" -s "name=$name" -s enabled=true -s publicClient=false -s clientAuthenticatorType=client-secret -s serviceAccountsEnabled=true -s standardFlowEnabled=false -s directAccessGrantsEnabled=false >/dev/null
  fi
  printf '%s' "$id"
}

ensure_audience_mapper() {
  local id="$1"
  if ! kc get "clients/$id/protocol-mappers/models" -r "$realm" --fields name --format csv --noquotes | grep -qx audience-codementor-api; then
    kc create "clients/$id/protocol-mappers/models" -r "$realm" \
      -s name=audience-codementor-api \
      -s protocol=openid-connect \
      -s protocolMapper=oidc-audience-mapper \
      -s 'config={"included.client.audience":"codementor-api","access.token.claim":"true","id.token.claim":"false"}' >/dev/null
  fi
}

ensure_user() {
  local username="$1"
  local email="$2"
  local first_name="$3"
  local role="$4"
  local password="$5"
  if ! kc get users -r "$realm" -q "username=$username" --fields id --format csv --noquotes | grep -q .; then
    kc create users -r "$realm" -s "username=$username" -s "email=$email" -s "firstName=$first_name" -s enabled=true -s emailVerified=true >/dev/null
  fi
  kc set-password -r "$realm" --username "$username" --new-password "$password" >/dev/null
  kc add-roles -r "$realm" --uusername "$username" --rolename "$role" >/dev/null 2>&1 || true
}

docker exec "$container" "$kcadm" config credentials \
  --config "$config_file" \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

if ! kc get "realms/$realm" >/dev/null 2>&1; then
  kc create realms -s "realm=$realm" -s enabled=true -s 'displayName=CodeMentor' >/dev/null
fi

kc update "realms/$realm" \
  -s enabled=true \
  -s loginTheme=codementor \
  -s sslRequired=EXTERNAL \
  -s registrationAllowed=false \
  -s registrationEmailAsUsername=true \
  -s loginWithEmailAllowed=true \
  -s duplicateEmailsAllowed=false \
  -s resetPasswordAllowed=true \
  -s verifyEmail=false >/dev/null

ensure_realm_role STUDENT 'CodeMentor student'
ensure_realm_role LECTURER 'CodeMentor lecturer'
ensure_realm_role ADMIN 'CodeMentor administrator'
ensure_realm_role AI_AGENT 'CodeMentor machine identity'

# Normalize the legacy imported default role to Keycloak's standard composite role.
if kc get roles/learner -r "$realm" >/dev/null 2>&1; then
  kc update roles/learner -r "$realm" -s "name=default-roles-$realm" -s 'description=Default CodeMentor roles' >/dev/null
fi
kc remove-roles -r "$realm" --rname "default-roles-$realm" --rolename STUDENT >/dev/null 2>&1 || true

for legacy_role in lecturer mentor; do
  if kc get "roles/$legacy_role" -r "$realm" >/dev/null 2>&1; then
    kc delete "roles/$legacy_role" -r "$realm" >/dev/null
  fi
done

admin_redirects="${KEYCLOAK_ADMIN_REDIRECT_URIS:-[\"http://localhost:3011/*\",\"http://13.214.122.227:3011/*\"]}"
admin_origins="${KEYCLOAK_ADMIN_WEB_ORIGINS:-[\"http://localhost:3011\",\"http://13.214.122.227:3011\"]}"
admin_client_id="$(ensure_public_client codementor-admin 'CodeMentor Admin' "$admin_redirects" "$admin_origins" codementor)"

lecturer_redirects="${KEYCLOAK_LECTURER_REDIRECT_URIS:-[\"http://localhost:3010/*\",\"http://13.214.122.227:3010/*\"]}"
lecturer_origins="${KEYCLOAK_LECTURER_WEB_ORIGINS:-[\"http://localhost:3010\",\"http://13.214.122.227:3010\"]}"
lecturer_client_id="$(ensure_public_client codementor-lecturer 'CodeMentor Lecturer' "$lecturer_redirects" "$lecturer_origins" codementor-lecturer)"
api_client_id="$(ensure_bearer_client)"
user_service_client_id="$(ensure_service_client codementor-user-service 'CodeMentor User Service')"
ai_client_id="$(ensure_service_client codementor-ai-agent 'CodeMentor AI Agent')"

ensure_audience_mapper "$admin_client_id"
ensure_audience_mapper "$lecturer_client_id"
ensure_audience_mapper "$ai_client_id"

kc add-roles -r "$realm" --uusername service-account-codementor-ai-agent --rolename AI_AGENT >/dev/null 2>&1 || true
for role in query-users view-users manage-users; do
  kc add-roles -r "$realm" --uusername service-account-codementor-user-service --cclientid realm-management --rolename "$role" >/dev/null 2>&1 || true
done

user_service_secret="$(kc get "clients/$user_service_client_id/client-secret" -r "$realm" --fields value --format csv --noquotes | tail -n 1)"
ai_secret="$(kc get "clients/$ai_client_id/client-secret" -r "$realm" --fields value --format csv --noquotes | tail -n 1)"
upsert_env KEYCLOAK_USER_SERVICE_CLIENT_SECRET "$user_service_secret"
upsert_env KEYCLOAK_AI_AGENT_CLIENT_SECRET "$ai_secret"

ensure_secret_env KEYCLOAK_DEV_STUDENT_PASSWORD
ensure_secret_env KEYCLOAK_DEV_LECTURER_PASSWORD
ensure_secret_env KEYCLOAK_DEV_ADMIN_PASSWORD
ensure_user student@codementor.dev student@codementor.dev Student STUDENT "$KEYCLOAK_DEV_STUDENT_PASSWORD"
ensure_user lecturer@codementor.dev lecturer@codementor.dev Lecturer LECTURER "$KEYCLOAK_DEV_LECTURER_PASSWORD"
ensure_user admin@codementor.dev admin@codementor.dev Admin ADMIN "$KEYCLOAK_DEV_ADMIN_PASSWORD"

chmod 600 .env
echo "CodeMentor realm, roles, clients, service accounts, and DEV users are configured."
