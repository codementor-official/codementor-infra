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

Currently implemented:

- `database/` — PostgreSQL migrations (29, append-only) + MongoDB schemas and seed.
- `docker/` — the deployed EC2 stack: PostgreSQL 18, MongoDB 7, Keycloak 26.7.0, plus the
  bootstrap/migrate/realm/verify scripts. This is running in production on
  `13.214.122.227` (AWS account `416069841933`, ap-southeast-1, t3.small).

Planned, not written: `k8s/`, `cicd/`, `monitoring/`, `deploy/` (Terraform + Ansible).
The README still shows those folders in its tree — treat that tree as the target shape, not as
what exists. `docs/` and `scripts/` at the repo root hold use-case models and diagram tooling;
they predate the one-folder-per-area rule and are the documented exception to it.

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
- A README that describes a safer configuration than the host actually runs is worse than no
  README. Before claiming a port is closed or a service is bound to loopback, check the host:
  `sudo ss -lntp`. Fix the claim or fix the host — never leave them disagreeing.
- Migrations are append-only: add a new numbered file, never edit an applied one.
- Environment-specific values stay out of committed configuration.

## Verifying changes

Database changes must pass `make database/verify` (invariant + dependency-guard suite)
against a freshly rebuilt stack: `make database/reset`. Do not claim a change works
without running it.

Changes to `docker/` are verified on the target host with `docker/scripts/verify-stack.sh`, then
by re-reading `sudo ss -lntp` to confirm the listening addresses match what the README promises.

Note for anyone editing `docker/docker-compose.dev.yml`: the bind mount is resolved by inode, so
`git pull` replacing a config file leaves the container reading the old contents. Restart the
container after any pull that touches a mounted file.
