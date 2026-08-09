# codementor-infra

Database architecture and data model for **CodeMentor** — PostgreSQL for the relational learning
domain, MongoDB for document-oriented learning content.

Derived from a full review of `codementor-frontend`; the review, the resulting domain model and
every design trade-off are written down in [`docs/`](docs/).

## Quick start

```bash
cp .env.example .env
make up        # postgres + mongo via docker compose, waits for health
make init      # apply all migrations, create collections + indexes
make seed      # sample data covering every dependency shape
make verify    # invariant + dependency-guard suite — must print ALL CHECKS PASSED
```

`make reset` rebuilds everything from empty volumes.
`make schema-doc` regenerates the table reference from the live database.

Without Docker, point `.env` at any PostgreSQL 14+ and MongoDB 6+ and run the same
`make init/seed/verify`.

> **Windows + đường dẫn có dấu tiếng Việt:** GNU Make 3.81 (bản đi kèm Git for Windows) không
> tìm được `Makefile` nếu thư mục cha chứa ký tự có dấu. Dùng `make -f Makefile <target>`, hoặc
> đặt repo ở đường dẫn không dấu. Các script trong `scripts/` chạy trực tiếp thì không bị ảnh hưởng.
>
> `mongosh` không cần cài trên máy — `scripts/init-mongo.sh` tự dùng bản có sẵn trong container.

## Layout

```
docs/
  00-frontend-review.md     entity/field inventory + what changed and why
  01-domain-model.md        entities, ERDs, relationship rules, progress strategy
  02-dependency-model.md    the prerequisite mechanism, per level, with diagrams
  03-mongodb-model.md       collections, document shapes, embedded-vs-referenced, indexes
  04-design-decisions.md    trade-offs and their costs
  05-schema-reference.md    every table, column, constraint and FK — GENERATED, do not hand-edit

postgres/
  migrations/0001…0013.sql  ordered, transactional, run top to bottom on an empty database
  seed/0001_seed.sql        linear / branching / unconstrained / AND / OR / mode-override
  verify.sql                asserts cache invariants and that invalid graphs are rejected

mongo/
  schemas/*.js              $jsonSchema validators + index definitions, one per collection
  init.js                   applies all of the above (idempotent)
  seed/seed.js              bodies matching the postgres seed's content_ref values

scripts/                    init-postgres.sh, init-mongo.sh
```

## The model in one page

```
Roadmap ──< roadmap_courses >── Course ──< Chapter ──< Lesson ──? Exercise
                  │                │          │          │           │
                  └─ prerequisites ┴──────────┴──────────┴───────────┘
                     (separate from `position`, which is display order only)
```

Four rules the schema is built around:

1. **Ordering ≠ dependency.** `position` says where something renders; `*_prerequisites` rows say
   what must be finished first. A lesson can be second in the list with no prerequisite.
2. **One dependency mechanism, five levels.** `(target, source, group_index)` — same group = AND,
   different groups = OR. Branching, multiple prerequisites and alternatives all fall out of it.
3. **Constrained and unconstrained learning share one dataset.** `progression_mode`
   (`linear` | `graph` | `free`) decides whether edges are enforced; learners can override it per
   enrolment. Nothing is duplicated to support either mode.
4. **Content is not per-user state.** Availability and progress are computed per learner
   (`fn_lesson_available`, `lesson_progress`), never stored on the shared content row.

## Where data lives

| PostgreSQL | MongoDB |
| --- | --- |
| users, preferences, groups, permissions | exercise statements, test cases, hints, language config |
| roadmaps, courses, chapters, lessons | lesson bodies (sections, blocks, media) |
| exercise identity, status, XP, difficulty | per-test judge output |
| all dependency edges + cycle guards | article bodies |
| enrolments, progress, submissions | |

Exercises are deliberately split — identity in PostgreSQL so dependencies, progress and
submissions have real foreign keys; body in MongoDB because its shape varies per kind and
language. Reasoning in [`docs/04-design-decisions.md §1`](docs/04-design-decisions.md).

## Status

Schema, constraints, triggers, indexes, seed data and verification are complete and tested
against PostgreSQL 18. No application logic — that is the next phase.
