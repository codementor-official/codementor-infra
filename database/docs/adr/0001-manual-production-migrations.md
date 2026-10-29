# 0001. Apply production migrations by hand until the ledger is backfilled

- Status: accepted 2026-09-27, still in force
- Scope: `database/migrations`, `infra_schema_migrations` on production

## Context

On production, `infra_schema_migrations` records only 19 of the first 31 files. Migrations
0019–0021 and 0023–0029 were applied by backend scripts or by hand and never recorded.
`migrate-postgres.sh` trusts the ledger, so running it on production would replay those files.

A fresh database built only from this repo also lacks tables that older backend scripts created,
so a migration that drops or alters them must not assume they exist.

## Decision

- Do not run `migrate-postgres.sh` against production.
- Apply each new migration with
  `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f <file>` (strip `?schema=` from the URL first), then
  `INSERT INTO infra_schema_migrations(filename) VALUES ('<file>')`.
- Rehearse first: on a freshly rebuilt local stack, then on production inside a transaction that
  ends in `ROLLBACK`.
- Migrations that touch legacy tables guard with `to_regclass(...)` / `IF EXISTS` (as 0030 does).

## Consequences

- Every production migration is a manual, two-step job. Forgetting the `INSERT` widens the drift.
- Backfilling the ledger for 0019–0021 and 0023–0029, after checking each file against the
  production schema, is the open task that makes `migrate-postgres.sh` safe again.
- `make database/reset` was already broken at the time (0026 and the seed need objects created by
  backend scripts). It needs its own fix.
