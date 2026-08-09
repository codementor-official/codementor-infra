# CLAUDE.md

Infrastructure repository for the CodeMentor platform. No application source code lives here.

## Layout

Each top-level folder is a self-contained infrastructure area that owns its own
`Makefile`, `README.md`, `docs/`, and (when the area gets complex) its own `CLAUDE.md`.

```text
codementor-infra/
├── Makefile        # dispatcher only — no real work happens here
├── CLAUDE.md       # this file
├── README.md
└── <area>/         # database/, docker/, k8s/, cicd/, monitoring/, scripts/
    ├── Makefile
    ├── README.md
    ├── docs/
    └── CLAUDE.md   # optional, add when the area needs it
```

Currently implemented: `database/` (PostgreSQL + MongoDB). Everything else is planned.

## Commands

Run everything through `make` from the repo root:

```bash
make help                # targets + discovered subfolders
make <area>              # that area's own help
make <area>/<target>     # one target in one area, e.g. make database/psql
make up|down|init|seed|verify|reset   # broadcast to every area that defines it
```

The root `Makefile` auto-discovers `*/Makefile` — a new area needs no root change.
Never add real recipes to the root `Makefile`; put them in the area's own `Makefile`.

## Rules

- Work inside the relevant area folder. Don't create root-level `docs/`, `scripts/`, or
  config that belongs to one area.
- Documentation goes in `<area>/docs/`. Non-obvious infrastructure decisions must be
  documented there, not only in commit messages.
- Never commit secrets. Credentials come from `.env` (gitignored); every variable must be
  listed in the area's `.env.example` with a safe development default.
- Migrations are append-only: add a new numbered file, never edit an applied one.
- Environment-specific values stay out of committed configuration.

## Verifying changes

Database changes must pass `make database/verify` (invariant + dependency-guard suite)
against a freshly rebuilt stack: `make database/reset`. Do not claim a change works
without running it.
