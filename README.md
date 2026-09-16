# CodeMentor Infrastructure

Infrastructure repository for the **CodeMentor** platform.

This repository contains the infrastructure configuration required to develop, run, test, deploy, and operate CodeMentor services across different environments.

The repository is designed to keep infrastructure concerns separate from application source code while providing a consistent foundation for local development, CI/CD, deployment, and production operations.

---

## Architecture Overview

CodeMentor infrastructure is organized into several major areas:

```text
                         CodeMentor
                             │
              ┌──────────────┼──────────────┐
              │              │              │
          PostgreSQL      MongoDB        DevOps
              │              │              │
              └──────────────┼──────────────┤
                             │
                         CI/CD Pipeline
                             │
                       Deployment / K8s
                             │
                    Monitoring & Operations
```

The infrastructure is intentionally separated by responsibility:

* **Database** — Data persistence and database initialization.
* **Docker** — Containerized local development and service dependencies.
* **CI/CD** — Automated build, test, validation, and deployment pipelines.
* **Kubernetes** — Container orchestration and deployment configuration.
* **Monitoring** — Observability and operational infrastructure.
* **Scripts** — Utility scripts for development and infrastructure management.

Each area is self-contained: it owns its own `Makefile`, `README.md`, `docs/`, and — when the area becomes complex enough to need agent guidance — its own `CLAUDE.md`. There is no repository-wide `docs/` directory; documentation lives next to the infrastructure it describes.

---

# Repository Structure

```text
codementor-infra/
│
├── database/
│   ├── postgres/
│   │   ├── migrations/
│   │   └── seed/
│   ├── mongo/
│   │   ├── schemas/
│   │   └── seed/
│   ├── scripts/
│   ├── docs/
│   ├── docker-compose.yml
│   ├── Makefile
│   ├── README.md
│   └── CLAUDE.md
│
├── docker/
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   ├── docs/
│   ├── Makefile
│   └── README.md
│
├── k8s/
│   ├── base/
│   ├── overlays/
│   │   ├── development/
│   │   ├── staging/
│   │   └── production/
│   ├── docs/
│   ├── Makefile
│   ├── README.md
│   └── CLAUDE.md
│
├── cicd/
│   ├── workflows/
│   ├── docs/
│   ├── Makefile
│   └── README.md
│
├── monitoring/
│   ├── dashboards/
│   ├── alerts/
│   ├── docs/
│   ├── Makefile
│   └── README.md
│
├── scripts/
│   ├── setup/
│   ├── deployment/
│   ├── Makefile
│   └── README.md
│
├── Makefile
├── CLAUDE.md
├── .env.example
└── README.md
```

**The tree above is the target shape, not what exists today.** As of 2026-09-16 the repository
contains `database/`, `docker/`, a root `docs/` (use-case models and rendered diagrams) and a root
`scripts/` (diagram rendering). `k8s/`, `cicd/` and `monitoring/` have not been created.

The root `docs/` and `scripts/` predate the one-folder-per-area rule stated below and are the
documented exception to it. Do not add to them; new documentation goes in its area's `docs/`.

Conventions for every top-level area:

* `Makefile` — the area's own tasks. The root `Makefile` only dispatches to these.
* `README.md` — required. What the area is and how to run it.
* `docs/` — documentation belonging to that area. There is no shared root `docs/`.
* `CLAUDE.md` — optional. Add it only when the area's tasks become complex enough that an agent needs rules beyond the README (as with `database/`); skip it while the area is still simple.

---

# Task Orchestration

The root `Makefile` does no work itself. It discovers every `*/Makefile` and dispatches to it:

```bash
make help                # available targets and discovered areas
make database            # show the database area's own help
make database/psql       # run one target in one area
make up                  # broadcast: run "up" in every area that defines it
```

Broadcast targets are `up`, `down`, `init`, `seed`, `verify`, and `reset`. Areas that do not define a target are skipped. A new area needs no root change — adding its `Makefile` is enough.

---

# Database

The `database/` directory contains all database-related infrastructure.

```
docs/
  00-frontend-review.md     entity/field inventory + what changed and why
  01-domain-model.md        entities, ERDs, relationship rules, progress strategy
  02-dependency-model.md    the prerequisite mechanism, per level, with diagrams
  03-mongodb-model.md       collections, document shapes, embedded-vs-referenced, indexes
  04-design-decisions.md    trade-offs and their costs
  05-schema-reference.md    every table, column, constraint and FK — GENERATED, do not hand-edit
  06-actors.md              actor catalog + generalisation hierarchy (tiếng Việt)
  07-use-case-model.md      use case diagrams per package, include/extend, traceability (tiếng Việt)
  08-use-case-specifications.md   detailed flows for 8 key use cases (tiếng Việt)

## PostgreSQL

PostgreSQL is used for structured relational data that requires strong consistency and relationships.

Typical domains include:

* Users
* Learning Groups
* Group Members
* Learning Roadmaps
* Courses
* Chapters
* Lessons
* Enrollments
* Learning Progress
* Relational dependencies

Structure:

```text
database/postgres/
├── migrations/
├── seed/
└── verify.sql
```

PostgreSQL is responsible for relational integrity through:

* Primary keys
* Foreign keys
* Unique constraints
* Check constraints
* Indexes
* Transactional operations

---

## MongoDB

MongoDB is used for flexible document-oriented learning content, particularly exercises and practice materials.

Typical exercise data includes:

* Exercise description
* Constraints
* Examples
* Test cases
* Hints
* Tags
* Difficulty
* Supported programming languages
* Evaluation configuration
* Exercise metadata

Structure:

```text
database/mongo/
├── schemas/
├── seed/
└── init.js
```

MongoDB is intentionally separated from PostgreSQL so flexible exercise content does not unnecessarily complicate the relational model.

---

# Learning Domain

One of the main responsibilities of the database layer is supporting the CodeMentor learning system.

The core learning hierarchy is:

```text
Learning Roadmap
       │
       ▼
     Course
       │
       ▼
    Chapter
       │
       ▼
     Lesson
```

The system distinguishes between **display order** and **learning dependency**.

### Display order

Defines how content appears in the UI:

```text
Lesson 1
Lesson 2
Lesson 3
```

### Learning dependency

Defines whether content is available:

```text
Lesson 1
   ├── Lesson 2
   ├── Lesson 3
   └── Lesson 4
```

This allows CodeMentor to support both linear and branching learning paths.

---

# Learning Modes

The infrastructure supports different learning scenarios.

### Linear

```text
A → B → C
```

### Branching

```text
       ┌── B
A ─────┼── C
       └── D
```

### Multiple prerequisites

```text
A ──┐
    ├──> C
B ──┘
```

### Unconstrained

```text
A
B
C
D
```

These relationships are modeled explicitly rather than being inferred from display order.

---

# Docker

The `docker/` directory contains container configuration for local development and infrastructure services.

Typical services may include:

* PostgreSQL
* MongoDB
* Backend dependencies
* Supporting infrastructure

Example:

```text
docker/
├── docker-compose.yml
├── docker-compose.dev.yml
└── README.md
```

Docker provides a consistent environment for developers without requiring every infrastructure dependency to be installed directly on the host machine.

---

# CI/CD

The `cicd/` directory contains CI/CD configuration and supporting documentation.

The CI/CD pipeline is responsible for automating:

```text
Code Push
    │
    ▼
Validation
    │
    ├── Lint
    ├── Test
    └── Infrastructure Validation
    │
    ▼
Build
    │
    ▼
Deploy
```

Potential future responsibilities include:

* Infrastructure validation
* Database migration validation
* Docker image builds
* Security checks
* Deployment automation
* Environment promotion

CI/CD configuration should keep environment-specific secrets outside the repository.

---

# Kubernetes

The `k8s/` directory contains Kubernetes deployment configuration.

The structure separates common configuration from environment-specific configuration:

```text
k8s/
├── base/
└── overlays/
    ├── development/
    ├── staging/
    └── production/
```

This allows the same base infrastructure to be reused across multiple environments while keeping environment-specific configuration isolated.

---

# Monitoring & Observability

The `monitoring/` directory is reserved for infrastructure observability.

Potential responsibilities include:

* Metrics
* Dashboards
* Alerts
* Database monitoring
* Service health monitoring
* Infrastructure health checks

Example:

```text
monitoring/
├── dashboards/
├── alerts/
└── README.md
```

Monitoring configuration should be added as the runtime infrastructure becomes available.

---

# Scripts

The `scripts/` directory contains cross-area infrastructure utilities. Scripts that belong to a single area live with that area instead — database initialization, for example, lives in `database/scripts/`.

Example:

```text
scripts/
├── setup/
└── deployment/
```

Possible responsibilities:

* Local environment setup
* Deployment helpers
* Environment promotion utilities

Scripts should be deterministic and safe to execute repeatedly where possible.

---

# Documentation

Documentation lives inside the area it describes, in that area's `docs/` directory:

```text
database/docs/
docker/docs/
k8s/docs/
cicd/docs/
monitoring/docs/
```

This keeps documentation next to the configuration it explains, so an area stays self-contained instead of splitting across a shared root directory.

Documentation may include:

* Infrastructure architecture
* Database ERD
* Database design decisions
* Deployment architecture
* Environment configuration
* Operational procedures
* Troubleshooting guides

Infrastructure decisions that are not obvious from configuration should be documented in the relevant area's `docs/`.

---

# Environment Configuration

Environment-specific configuration must not be hard-coded into infrastructure files.

Use:

```text
.env.example
```

as a template for required variables.

Sensitive values such as:

* Passwords
* API keys
* Database credentials
* Tokens
* Cloud credentials

must not be committed to the repository.

Production secrets should be provided through the appropriate secret-management mechanism.

---

# Environment Strategy

The infrastructure is designed to support multiple environments:

```text
Development
     │
     ▼
  Staging
     │
     ▼
 Production
```

Each environment should have clearly separated:

* Configuration
* Credentials
* Database instances
* Deployment settings
* Monitoring configuration

Development configuration must never contain production credentials.

---

# Infrastructure Principles

The following principles guide this repository.

### 1. Separation of Concerns

Infrastructure configuration is separated from application source code.

### 2. Database Responsibility

Each database technology should be used according to its strengths.

### 3. Explicit Relationships

Important domain relationships and learning dependencies must be modeled explicitly.

### 4. Reproducibility

A new developer or environment should be able to reproduce the required infrastructure from repository configuration.

### 5. Environment Isolation

Development, staging, and production configuration must remain isolated.

### 6. Infrastructure as Code

Infrastructure configuration should be version-controlled and reproducible.

### 7. Security by Default

Secrets and sensitive credentials must never be committed to source control.

### 8. Incremental Evolution

Infrastructure should remain simple at the current stage while providing a clear path for future scaling.

---

# Current Scope

The infrastructure repository will progressively expand toward:

```text
Database
   │
   ├── Docker
   │
   ├── CI/CD
   │
   ├── Kubernetes
   │
   ├── Monitoring
   │
   └── Operations
```

Not every directory needs to be fully implemented immediately. The repository structure is designed to accommodate these components as CodeMentor development progresses.

---

# Related Repositories

The infrastructure repository is intended to work alongside the CodeMentor application repositories.

```text
CodeMentor
│
├── Frontend
├── Backend
├── AI / Execution Engine
└── codementor-infra
        │
        ├── Database
        ├── Docker
        ├── CI/CD
        ├── Kubernetes
        └── Monitoring
```

Application repositories should focus on business logic and application behavior, while `codementor-infra` owns the infrastructure required to run those applications.

---

# Development Workflow

A typical development workflow is:

```text
1. Clone repository
        ↓
2. Configure environment
        ↓
3. Start infrastructure
        ↓
4. Initialize databases
        ↓
5. Run migrations
        ↓
6. Load seed data
        ↓
7. Start CodeMentor services
```

Steps 3–6 are driven from the root `Makefile` (`make up`, `make init`, `make seed`, `make verify`). The exact commands for each area are documented in that area's `README.md` as it is implemented.

---

# Status

Updated 2026-09-16.

| Component | Status |
| --- | --- |
| PostgreSQL | ✅ Deployed on EC2, 29 migrations applied, holding real data |
| MongoDB | ✅ Deployed on EC2, holding real data |
| Keycloak | ✅ Deployed, behind Nginx + Let's Encrypt at `id.codementor.cloud` |
| Docker (`docker/`) | ✅ Compose stack + bootstrap/migrate/realm/verify scripts |
| Kafka, Kong | ❌ Not in this repo — run from `codementor-backend/docker-compose.yml` on the dev machine only |
| Terraform / Ansible | ❌ Not written |
| CI/CD | ❌ Not written — no `.github/workflows/` in any of the three repositories |
| Kubernetes | ❌ Not started, and out of scope for the thesis |
| Monitoring | ❌ Not started |
| Backups | ❌ **None.** No `pg_dump` or `mongodump` runs anywhere; the data on the EC2 host exists in one copy |

The backup row is the one to act on first. Everything else is a missing feature; that one is a
single instance failure away from losing the project's data.

---

# Goal

`codementor-infra` aims to become the **single source of truth for CodeMentor infrastructure**.

The repository should make it possible to:

* Reproduce the development environment.
* Initialize databases consistently.
* Manage infrastructure configuration.
* Automate validation and deployment.
* Maintain environment separation.
* Monitor deployed services.
* Evolve the platform without coupling infrastructure to application code.
