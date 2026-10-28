<div align="center">

# CodeMentor Infrastructure

**The data layer and identity stack of CodeMentor: PostgreSQL schema and migrations, MongoDB collections, Keycloak, and the host that runs them.**

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-7-47A248?logo=mongodb&logoColor=white)
![Keycloak](https://img.shields.io/badge/Keycloak-26.7-4D4D4D?logo=keycloak&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Make](https://img.shields.io/badge/Make-tasks-6D00CC?logo=gnu&logoColor=white)

</div>

---

## Contents

- [Overview](#overview)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [Database](#database)
- [Migrations](#migrations)
- [Keycloak](#keycloak)
- [Production host](#production-host)
- [Documentation](#documentation)
- [Conventions](#conventions)

## Overview

This repository holds infrastructure only — no application code. It **owns the database schema**:
the backend reads it through Prisma introspection and never migrates it. Every schema change is a
new numbered SQL migration here.

| Area | What it provides |
| --- | --- |
| `database/` | PostgreSQL migrations, seed data, invariant checks; MongoDB collection schemas and seed |
| `docker/` | The data host stack — PostgreSQL 18, MongoDB 7, Keycloak 26.7 — plus its operations scripts and the Keycloak login themes |
| `docs/` | Actors, use-case model and use-case specifications, with rendered diagrams |

## Repository layout

```text
codementor-infra/
├── database/
│   ├── postgres/
│   │   ├── migrations/      numbered, append-only SQL migrations
│   │   ├── seed/            development seed data
│   │   └── verify.sql       invariant and dependency-guard checks
│   ├── mongo/
│   │   ├── schemas/         collection validators and indexes
│   │   └── seed/
│   ├── scripts/             init, catalog dump, schema-reference generator
│   ├── docs/                domain model, dependency model, design decisions, schema reference
│   └── Makefile
├── docker/
│   ├── docker-compose.dev.yml
│   ├── keycloak/themes/     login themes: codementor, codementor-web, codementor-lecturer
│   ├── scripts/             bootstrap, migrate, realm configuration, stack verification
│   ├── docs/
│   └── Makefile
├── docs/                    use-case documentation and diagrams
├── scripts/                 diagram rendering
└── Makefile                 dispatcher only
```

## Getting started

**Prerequisites:** Docker with Compose, GNU Make, and `psql` for ad-hoc queries.

```bash
cp database/.env.example database/.env      # local credentials
make database/up                            # start PostgreSQL + MongoDB
make database/init                          # apply migrations and Mongo schemas
make database/seed                          # load development data
make database/verify                        # run the invariant checks
```

The root `Makefile` does no work itself; it discovers every `*/Makefile` and dispatches to it:

```bash
make help                 # targets and discovered areas
make database             # one area's help
make database/psql        # one target in one area
make up | down | init | seed | verify | reset   # broadcast to every area that defines it
```

## Database

### PostgreSQL

Relational, strongly consistent data: accounts, learning paths, courses, chapters, lessons,
enrollments and progress, exercises, study groups, submissions, commerce, notifications, content
reports and moderation history.

Integrity is enforced in the database, not only in application code — foreign keys, unique and
CHECK constraints, and triggers and PL/pgSQL functions that prevent dependency cycles and maintain
cached progress. These objects are the reason the backend must never run `prisma migrate`.

The learning model separates **display order** from **learning dependency**, so a path can be
linear, branching, have several prerequisites, or be unconstrained:

```text
Linear            Branching              Several prerequisites
A → B → C         A ─┬─ B                A ──┐
                     ├─ C                    ├──▶ C
                     └─ D                B ──┘
```

### MongoDB

Document content whose shape varies: lesson and exercise content, article bodies, submission run
details, notifications, and the AI assistant's sessions, documents and RAG index. Each collection
has a validator and its indexes in `database/mongo/schemas/`.

## Migrations

```text
database/postgres/migrations/0001_….sql … 0041_report_suspension_expiry.sql
```

- **Append-only.** Add a new numbered file; never edit one that has been applied.
- **Idempotent where possible** (`IF NOT EXISTS`, guarded `DO` blocks) and wrapped in a transaction.
- **Apply before deploying** the backend version that depends on the change.

`docker/scripts/migrate-postgres.sh` applies pending files and records each in
`infra_schema_migrations`. On the production host some migrations were applied by hand and are
not recorded there; check the table against the database before running the script, and apply a
single migration with `psql -f` when in doubt.

Every change must pass `make database/verify` against a freshly rebuilt stack
(`make database/reset`).

## Keycloak

Keycloak is the identity provider for all three frontend applications and the backend. The realm
is configured by `docker/scripts/configure-codementor-realm.sh`. Login pages use the themes under
`docker/keycloak/themes/`; theme caching is disabled, so changing a mounted theme file takes effect
without a restart.

Details: [`docker/docs/keycloak.md`](docker/docs/keycloak.md).

## Production host

The data host runs PostgreSQL, MongoDB and Keycloak from `docker/docker-compose.dev.yml`.
Keycloak binds to loopback and is published over TLS at `https://id.codementor.cloud`.

> **Security:** read [`docker/README.md`](docker/README.md) before changing the host. It records
> which ports are reachable from the Internet and the steps to close them.

## Documentation

| Document | Covers |
| --- | --- |
| [`database/docs/01-domain-model.md`](database/docs/01-domain-model.md) | Entities, relationships, progress strategy |
| [`database/docs/02-dependency-model.md`](database/docs/02-dependency-model.md) | The prerequisite mechanism at each level |
| [`database/docs/03-mongodb-model.md`](database/docs/03-mongodb-model.md) | Collections, document shapes, indexes |
| [`database/docs/04-design-decisions.md`](database/docs/04-design-decisions.md) | Trade-offs and their costs |
| [`database/docs/05-schema-reference.md`](database/docs/05-schema-reference.md) | Every table, column and constraint — generated, do not edit by hand |
| [`docs/06-actors.md`](docs/06-actors.md) · [`docs/07-use-case-model.md`](docs/07-use-case-model.md) · [`docs/08-use-case-specifications.md`](docs/08-use-case-specifications.md) | Actors, use cases and their specifications |
| [`docker/README.md`](docker/README.md) | The data host: services, ports, operations |

## Conventions

- Each top-level area owns its `Makefile`, `README.md` and `docs/`; the root `Makefile` only dispatches.
- Never commit secrets. Every variable is listed in the area's `.env.example` with a safe default.
- A README must not describe a safer configuration than the host actually runs — check the host
  (`sudo ss -lntp`) and fix the claim or the host.

## Related repositories

- **codementor-backend** — NestJS and Python services that read this schema.
- **codementor-frontend** — the learner, lecturer and admin applications.
