# CodeMentor EC2 development stack

This area runs the stateful development dependencies on one small EC2 host:

- PostgreSQL 18 for the CodeMentor relational schema and the separate Keycloak database.
- MongoDB 7 for lesson, exercise, submission-run, and article documents.
- Keycloak 26.7.0 for identity and access management.

The databases bind to `127.0.0.1` on the host and are not publicly exposed. Keycloak binds
to port `8080` for development. Restrict the EC2 security-group ingress for `22` and `8080`
to trusted developer IP addresses. Do not open PostgreSQL or MongoDB ports to the Internet.

## First deployment on Amazon Linux 2023

```bash
cd /opt/codementor-infra
sudo bash docker/scripts/bootstrap-amazon-linux.sh
cp docker/.env.example docker/.env
# Replace every placeholder in docker/.env before continuing.
sudo docker compose --env-file docker/.env -f docker/docker-compose.dev.yml up -d
sudo bash docker/scripts/migrate-postgres.sh
sudo bash docker/scripts/init-mongo.sh
sudo bash docker/scripts/verify-stack.sh
```

The bootstrap script installs Docker, verifies the Docker Compose binary checksum, enables
Docker at boot, and creates a 2 GiB swap file when the host has no swap. The Compose stack
uses named volumes and `unless-stopped`, so data and services survive host restarts.

## Access

- Keycloak Admin Console: `http://EC2_PUBLIC_IP:${KEYCLOAK_HTTP_PORT}/admin/`
- PostgreSQL from the EC2 host: `127.0.0.1:${POSTGRES_PORT}`
- MongoDB from the EC2 host: `127.0.0.1:${MONGO_PORT}`

For production, put Keycloak behind a TLS reverse proxy and replace the IP-based hostname
with a stable domain before integrating application clients.
