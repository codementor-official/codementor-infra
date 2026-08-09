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
* **Docs** — Infrastructure architecture and operational documentation.

---

# Repository Structure

```text
codementor-infra/
│
├── database/
│   ├── postgresql/
│   │   ├── migrations/
│   │   ├── seeds/
│   │   └── README.md
│   │
│   └── mongodb/
│       ├── indexes/
│       ├── seeds/
│       └── README.md
│
├── docker/
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── README.md
│
├── k8s/
│   ├── base/
│   ├── overlays/
│   │   ├── development/
│   │   ├── staging/
│   │   └── production/
│   └── README.md
│
├── cicd/
│   ├── workflows/
│   └── README.md
│
├── monitoring/
│   ├── dashboards/
│   ├── alerts/
│   └── README.md
│
├── scripts/
│   ├── setup/
│   ├── database/
│   └── deployment/
│
├── docs/
│   ├── architecture/
│   ├── database/
│   └── operations/
│
├── .env.example
└── README.md
```

Some directories may initially contain only documentation or configuration placeholders. They are intentionally separated to provide a consistent structure as the project grows.

---

# Database

The `database/` directory contains all database-related infrastructure.

CodeMentor uses two database technologies with different responsibilities.

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
database/postgresql/
├── migrations/
├── seeds/
└── README.md
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
database/mongodb/
├── indexes/
├── seeds/
└── README.md
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

The `scripts/` directory contains reusable infrastructure utilities.

Example:

```text
scripts/
├── setup/
├── database/
└── deployment/
```

Possible responsibilities:

* Local environment setup
* Database initialization
* Database reset
* Seed execution
* Migration utilities
* Deployment helpers

Scripts should be deterministic and safe to execute repeatedly where possible.

---

# Documentation

The `docs/` directory contains infrastructure-specific documentation.

```text
docs/
├── architecture/
├── database/
└── operations/
```

Documentation may include:

* Infrastructure architecture
* Database ERD
* Database design decisions
* Deployment architecture
* Environment configuration
* Operational procedures
* Troubleshooting guides

Infrastructure decisions that are not obvious from configuration should be documented here.

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

The current focus is:

```text
Database Foundation
        │
        ├── PostgreSQL
        │
        └── MongoDB
```

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

The exact commands will be documented in the relevant directory README files as each infrastructure component is implemented.

---

# Status

| Component     | Status                    |
| ------------- | ------------------------- |
| PostgreSQL    | 🚧 Initial implementation |
| MongoDB       | 🚧 Initial implementation |
| Docker        | Planned / In progress     |
| CI/CD         | Planned                   |
| Kubernetes    | Planned                   |
| Monitoring    | Planned                   |
| Operations    | Planned                   |
| Documentation | In progress               |

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
