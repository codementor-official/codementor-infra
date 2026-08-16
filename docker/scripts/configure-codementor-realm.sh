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

# The ONLY client in the realm allowed to use Direct Access Grant.
#
# apps/web renders its own username/password form, so the credentials reach Keycloak
# through the Next.js BFF (`POST /api/auth/login`) instead of a browser redirect. That
# needs the password grant — but a public client with the password grant enabled lets
# anyone on the internet replay credentials against the realm with nothing but the
# client id. Hence a separate CONFIDENTIAL client: the grant is useless without the
# secret, and the secret never leaves the server.
#
# `standardFlowEnabled=false` on purpose — this client must never be usable for a
# browser redirect flow. That stays with the public `codementor-web` client, which
# keeps `directAccessGrantsEnabled=false`.
#
# The service account exists for self-registration: Keycloak has no public sign-up API,
# so the only way to keep the sign-up form inside Next.js is for the BFF to create the
# account through the Admin REST API. It gets `manage-users` and nothing else.
ensure_bff_client() {
  local id
  id="$(client_id codementor-web-bff)"
  if [ -z "$id" ]; then
    id="$(kc create clients -r "$realm" -s clientId=codementor-web-bff -s 'name=CodeMentor Web BFF' -s enabled=true -s publicClient=false -s clientAuthenticatorType=client-secret -s serviceAccountsEnabled=true -s standardFlowEnabled=false -s directAccessGrantsEnabled=true -i)"
  else
    kc update "clients/$id" -r "$realm" -s 'name=CodeMentor Web BFF' -s enabled=true -s publicClient=false -s clientAuthenticatorType=client-secret -s serviceAccountsEnabled=true -s standardFlowEnabled=false -s directAccessGrantsEnabled=true >/dev/null
  fi
  printf '%s' "$id"
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


# Google/Facebook OAuth apps. Both providers only ever hand back a confirmed email
# through their basic `email` scope, so `trustEmail=true` is safe here — it lets
# Keycloak's stock "first broker login" flow offer to LINK a matching existing
# account (confirmed by the user re-entering their password) instead of either
# silently merging or creating a second account. No custom auth flow needed; this
# is Keycloak's default behavior once the IdP is marked as trusted.
ensure_identity_provider() {
  local alias="$1"
  local provider_id="$2"
  local client_id_var="$3"
  local client_secret_var="$4"
  # Optional extra `config.*` settings, e.g. Google's prompt behaviour.
  shift 4
  local client_id="${!client_id_var:-}"
  local client_secret="${!client_secret_var:-}"
  local extra=()
  local setting
  for setting in "$@"; do
    extra+=(-s "$setting")
  done
  if [ -z "$client_id" ] || [ -z "$client_secret" ]; then
    echo "skip identity provider '$alias': $client_id_var/$client_secret_var not set in .env"
    return
  fi
  if kc get "identity-provider/instances/$alias" -r "$realm" >/dev/null 2>&1; then
    kc update "identity-provider/instances/$alias" -r "$realm" \
      -s enabled=true \
      -s trustEmail=true \
      -s storeToken=false \
      -s "config.clientId=$client_id" \
      -s "config.clientSecret=$client_secret" \
      "${extra[@]}" >/dev/null
  else
    kc create identity-provider/instances -r "$realm" \
      -s "alias=$alias" \
      -s "providerId=$provider_id" \
      -s enabled=true \
      -s trustEmail=true \
      -s storeToken=false \
      -s "config.clientId=$client_id" \
      -s "config.clientSecret=$client_secret" \
      "${extra[@]}" >/dev/null
  fi
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

# Keycloak's stock user profile marks firstName AND lastName as required for every
# human account. Two consequences CodeMentor does not want:
#
#   - Direct Access Grant refuses any account missing either one with the unhelpful
#     "Account is not fully set up". Vietnamese sign-up collects a single "Họ và tên",
#     so a brand-new account trips this on its very first login.
#   - In a browser flow Keycloak answers with its own "complete your profile" page —
#     the exact screen the Next.js UI is meant to replace.
#
# The names are still stored and still shown; they are just not mandatory. Email stays
# required, because that is what identifies the account.
ensure_user_profile() {
  kc get users/profile -r "$realm" \
    | jq '.attributes |= map(if .name == "firstName" or .name == "lastName" then del(.required) else . end)' \
    | docker exec -i "$container" "$kcadm" update users/profile -r "$realm" --config "$config_file" -f - >/dev/null
}

# First login through Google/Facebook must land straight inside CodeMentor.
#
# `idp-review-profile` defaults to "missing", which means Keycloak shows its own
# review-profile page whenever the identity provider did not hand over every required
# field — Facebook in particular does not always return a family name. Turning it off
# lets Keycloak create the account silently from the IdP claims; anything else
# CodeMentor needs is asked for by the onboarding UI in apps/web.
ensure_first_broker_login_silent() {
  local executions
  local config_id
  local execution_id
  executions="$(kc get "authentication/flows/first%20broker%20login/executions" -r "$realm")"
  config_id="$(printf '%s' "$executions" | jq -r '.[] | select(.providerId == "idp-review-profile") | .authenticationConfig // empty')"
  if [ -n "$config_id" ]; then
    kc update "authentication/config/$config_id" -r "$realm" -s 'config."update.profile.on.first.login"=off' >/dev/null
  else
    execution_id="$(printf '%s' "$executions" | jq -r '.[] | select(.providerId == "idp-review-profile") | .id')"
    kc create "authentication/executions/$execution_id/config" -r "$realm" \
      -s alias=codementor-review-profile \
      -s 'config."update.profile.on.first.login"=off' >/dev/null
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

# `bruteForceProtected`: apps/web now sends passwords through its own BFF, so Keycloak
# no longer sees a browser it can throttle by itself. Brute-force detection applies to
# the password grant exactly as it does to the hosted login page, and it is the backstop
# behind the per-IP limiter in the BFF route.
kc update "realms/$realm" \
  -s enabled=true \
  -s loginTheme=codementor \
  -s sslRequired=EXTERNAL \
  -s registrationAllowed=true \
  -s registrationEmailAsUsername=true \
  -s loginWithEmailAllowed=true \
  -s duplicateEmailsAllowed=false \
  -s resetPasswordAllowed=true \
  -s verifyEmail=false \
  -s bruteForceProtected=true \
  -s internationalizationEnabled=true \
  -s 'supportedLocales=["vi"]' \
  -s defaultLocale=vi >/dev/null

ensure_user_profile
ensure_first_broker_login_silent

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
web_bff_client_id="$(ensure_bff_client)"
user_service_client_id="$(ensure_service_client codementor-user-service 'CodeMentor User Service')"
ai_client_id="$(ensure_service_client codementor-ai-agent 'CodeMentor AI Agent')"

ensure_audience_mapper "$admin_client_id"
ensure_audience_mapper "$lecturer_client_id"
ensure_audience_mapper "$ai_client_id"
# Without this the password-grant token carries no `codementor-api` audience and every
# backend call behind Kong rejects it — the login succeeds and the app still looks broken.
ensure_audience_mapper "$web_bff_client_id"

# `prompt=select_account`: after logging out of CodeMentor, clicking "Tiếp tục với
# Google" must let the user pick an account. Without it Google silently reuses whichever
# account is signed in to the browser, so logging out and back in as somebody else is
# impossible without leaving Google entirely. Facebook's OAuth has no equivalent, hence
# the setting only goes on Google.
ensure_identity_provider google google GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET config.prompt=select_account
ensure_identity_provider facebook facebook FACEBOOK_CLIENT_ID FACEBOOK_CLIENT_SECRET

kc add-roles -r "$realm" --uusername service-account-codementor-ai-agent --rolename AI_AGENT >/dev/null 2>&1 || true
# Self-registration from apps/web: create the account, set its password, grant STUDENT.
# `manage-users` is the narrowest realm-management role that covers all three.
kc add-roles -r "$realm" --uusername service-account-codementor-web-bff --cclientid realm-management --rolename manage-users >/dev/null 2>&1 || true
for role in query-users view-users manage-users; do
  kc add-roles -r "$realm" --uusername service-account-codementor-user-service --cclientid realm-management --rolename "$role" >/dev/null 2>&1 || true
done

user_service_secret="$(kc get "clients/$user_service_client_id/client-secret" -r "$realm" --fields value --format csv --noquotes | tail -n 1)"
ai_secret="$(kc get "clients/$ai_client_id/client-secret" -r "$realm" --fields value --format csv --noquotes | tail -n 1)"
web_bff_secret="$(kc get "clients/$web_bff_client_id/client-secret" -r "$realm" --fields value --format csv --noquotes | tail -n 1)"
upsert_env KEYCLOAK_USER_SERVICE_CLIENT_SECRET "$user_service_secret"
upsert_env KEYCLOAK_AI_AGENT_CLIENT_SECRET "$ai_secret"
# Copy into apps/web/.env.local as KEYCLOAK_BFF_CLIENT_SECRET. Server-side only — it
# must never appear under a NEXT_PUBLIC_ name.
upsert_env KEYCLOAK_WEB_BFF_CLIENT_SECRET "$web_bff_secret"

ensure_secret_env KEYCLOAK_DEV_STUDENT_PASSWORD
ensure_secret_env KEYCLOAK_DEV_LECTURER_PASSWORD
ensure_secret_env KEYCLOAK_DEV_ADMIN_PASSWORD
ensure_user student@codementor.dev student@codementor.dev Student STUDENT "$KEYCLOAK_DEV_STUDENT_PASSWORD"
ensure_user lecturer@codementor.dev lecturer@codementor.dev Lecturer LECTURER "$KEYCLOAK_DEV_LECTURER_PASSWORD"
ensure_user admin@codementor.dev admin@codementor.dev Admin ADMIN "$KEYCLOAK_DEV_ADMIN_PASSWORD"

chmod 600 .env
echo "CodeMentor realm, roles, clients, service accounts, and DEV users are configured."
