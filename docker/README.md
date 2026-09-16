# CodeMentor EC2 development stack

This area runs the stateful development dependencies on one small EC2 host:

- PostgreSQL 18 for the CodeMentor relational schema and the separate Keycloak database.
- MongoDB 7 for lesson, exercise, submission-run, and article documents.
- Keycloak 26.7.0 for identity and access management.

## What the deployed host actually runs

Verified on `13.214.122.227` (AWS account `416069841933`, ap-southeast-1c, t3.small, 2 GB RAM)
on 2026-09-16 with `sudo ss -lntp`:

| Port | Bound to | Reached by |
| --- | --- | --- |
| 22 | `0.0.0.0` | SSH, key only |
| 80, 443 | `0.0.0.0` | Nginx 1.30.4 → `id.codementor.cloud`, Let's Encrypt |
| 8080 | `127.0.0.1` | Keycloak, **loopback only** — Nginx is the sole public entry |
| 5432 | `0.0.0.0` | PostgreSQL — **open to the Internet** |
| 27017 | `0.0.0.0` | MongoDB — **open to the Internet** |

> ⚠️ **PostgreSQL and MongoDB are currently reachable from anywhere.** The host is running with
> `POSTGRES_BIND_ADDRESS=0.0.0.0` and `MONGO_BIND_ADDRESS=0.0.0.0`, and these ports hold the real
> project data. An earlier version of this README claimed both were bound to `127.0.0.1`; that
> claim was wrong, and a README that describes a safer setup than the host runs is how a hole
> stays open for weeks.
>
> The security group is the only thing in front of them. Restrict ingress on `5432` and `27017`
> to specific source addresses — a developer IP, or the application host's Elastic IP — and
> nothing else. To work against the database from a laptop without opening the port, tunnel:
>
> ```bash
> ssh -i codementor.pem -L 5432:localhost:5432 ec2-user@13.214.122.227
> ```
>
> Credentials that have been shared in plain-text files should be rotated once the ports are
> closed, in this order: close the ports, rotate, then update every consumer's `.env`.

Keycloak needs no such warning: it binds to loopback and is served over TLS by Nginx. That is why
`KEYCLOAK_HOSTNAME` is `https://id.codementor.cloud` and why applications must use that issuer —
pointing at `http://13.214.122.227:8080` makes sign-in appear to succeed and then fails every
subsequent API call with 401, because the `iss` claim will not match.

## First deployment on Amazon Linux 2023

```bash
cd /opt/codementor-infra
sudo bash docker/scripts/bootstrap-amazon-linux.sh
cp docker/.env.example docker/.env
# Replace every placeholder in docker/.env before continuing.
sudo docker compose --env-file docker/.env -f docker/docker-compose.dev.yml up -d
sudo bash docker/scripts/migrate-postgres.sh
sudo bash docker/scripts/init-mongo.sh
sudo bash docker/scripts/configure-keycloak-dev.sh
sudo bash docker/scripts/configure-codementor-realm.sh
sudo bash docker/scripts/verify-stack.sh
```

Then put Nginx and a certificate in front of Keycloak — the compose file binds it to
`127.0.0.1:8080`, so without a reverse proxy nothing outside the host can reach it at all.
The deployed host serves `id.codementor.cloud` from `/etc/nginx/conf.d/id-codementor.conf`
with a Let's Encrypt certificate under `/etc/letsencrypt/live/id.codementor.cloud/`.

After any `git pull` that touches a mounted file (`kong.yml`, a Keycloak theme,
`docker-compose.dev.yml`), **restart the affected container**. The bind mount resolves to an
inode; git replaces the file rather than editing it in place, so the container keeps serving the
old contents and the change appears to have had no effect.

The Keycloak configuration step sets `sslRequired=NONE` on the `master` realm so its admin
console works over an EC2 IP address during development. Never apply this setting in production;
use a stable hostname and TLS instead.

Realm roles, OIDC clients, service accounts, DEV identities, and audience mapping are documented
in [`docs/keycloak.md`](docs/keycloak.md).

The bootstrap script installs Docker, verifies the Docker Compose binary checksum, enables
Docker at boot, and creates a 2 GiB swap file when the host has no swap. The Compose stack
uses named volumes and `unless-stopped`, so data and services survive host restarts.

## Access

- Keycloak Admin Console: `https://id.codementor.cloud/admin/`
- OIDC discovery: `https://id.codementor.cloud/realms/codementor/.well-known/openid-configuration`
- PostgreSQL from the EC2 host: `127.0.0.1:${POSTGRES_PORT}`
- MongoDB from the EC2 host: `127.0.0.1:${MONGO_PORT}`

## Resource budget

The host is a t3.small: 2 vCPU, 2 GB RAM, 50 GB gp3, plus a 2 GiB swap file the bootstrap script
creates. Measured 2026-09-16 — Keycloak 526 MB of its 768 MB limit, PostgreSQL 50 MB, MongoDB
58 MB, leaving about **769 MB available**.

That is why this stack holds only the three stateful services. Kafka (a JVM), Kong, and the
eleven application services do not fit here and belong on a separate, larger host; see
`../plan-deploy-aws.md` in the workspace root.
