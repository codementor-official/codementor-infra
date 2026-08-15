# Keycloak DEV authentication

The `codementor` login theme is mounted from `docker/keycloak/themes/codementor` and selected by the idempotent realm configuration script. It keeps credentials inside Keycloak while matching the CodeMentor Admin visual language.

`docker/scripts/configure-codementor-realm.sh` is the reproducible source of truth for the
CodeMentor realm. It is safe to run again after configuration changes.

```bash
cd /opt/codementor-infra
sudo bash docker/scripts/configure-codementor-realm.sh
```

## Realm and roles

Realm: `codementor`

| Realm role | Identity |
| --- | --- |
| `STUDENT` | Human student |
| `LECTURER` | Human lecturer |
| `ADMIN` | Human platform administrator |
| `AI_AGENT` | Service accounts only |

Guest is the absence of a token, not a role. The DEV realm allows HTTP because it currently
runs on an EC2 IP. Production must use a stable hostname, TLS, and `sslRequired=external` or
`all`.

## Clients

| Client | Type and flow | Purpose |
| --- | --- | --- |
| `codementor-admin` | Public, Authorization Code, PKCE S256 | Next.js Admin app |
| `codementor-api` | Bearer-only audience | NestJS resource server |
| `codementor-user-service` | Confidential service account | Keycloak Admin API |
| `codementor-ai-agent` | Confidential service account | Client Credentials + `AI_AGENT` |

The admin and AI Agent access tokens include the `codementor-api` audience. The user-service
service account receives only `query-users`, `view-users`, and `manage-users` from the built-in
`realm-management` client. Client secrets are generated into the target host's ignored
`docker/.env`; they are never stored in Git or exposed to the browser.

Admin redirect URIs and web origins are supplied as JSON arrays:

```env
KEYCLOAK_ADMIN_REDIRECT_URIS=["http://localhost:3002/*"]
KEYCLOAK_ADMIN_WEB_ORIGINS=["http://localhost:3002"]
```

Add the deployed Admin origin to both variables before running the script in another DEV
environment. No client secret belongs in `NEXT_PUBLIC_*` variables.

## DEV identities

The configuration script creates these examples and stores generated passwords only in the
target host's `docker/.env`:

```text
student@codementor.dev  -> STUDENT
lecturer@codementor.dev -> LECTURER
admin@codementor.dev    -> ADMIN
```

## AI Agent token

```bash
curl -X POST "$KEYCLOAK_URL/realms/codementor/protocol/openid-connect/token" \
  -d grant_type=client_credentials \
  -d client_id=codementor-ai-agent \
  -d client_secret="$KEYCLOAK_AI_AGENT_CLIENT_SECRET"
```

The resulting access token must contain realm role `AI_AGENT` and audience
`codementor-api`. It does not grant `ADMIN`.
