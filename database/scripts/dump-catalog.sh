#!/usr/bin/env bash
# Dumps the live catalog into pipe-separated files for scripts/gen-schema-doc.js.
#   bash scripts/dump-catalog.sh <outDir>
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

OUT="${1:-.catalog}"
mkdir -p "$OUT"

HOST="${POSTGRES_HOST:-localhost}"
PORT="${POSTGRES_PORT:-55432}"
USER="${POSTGRES_USER:-codementor}"
DB="${POSTGRES_DB:-codementor}"
export PGPASSWORD="${POSTGRES_PASSWORD:-codementor}"

PSQL=(psql -tAF'|' -h "$HOST" -p "$PORT" -U "$USER" -d "$DB")

"${PSQL[@]}" > "$OUT/cols.txt" <<'SQL'
select c.relname, a.attnum, a.attname,
       format_type(a.atttypid, a.atttypmod),
       case when a.attnotnull then 'NOT NULL' else '' end,
       coalesce(pg_get_expr(d.adbin, d.adrelid), '')
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname, a.attnum;
SQL

"${PSQL[@]}" > "$OUT/fks.txt" <<'SQL'
select src.relname, con.conname,
       (select string_agg(att.attname, ',' order by k.ord)
          from unnest(con.conkey) with ordinality k(attnum, ord)
          join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum),
       tgt.relname,
       (select string_agg(att.attname, ',' order by k.ord)
          from unnest(con.confkey) with ordinality k(attnum, ord)
          join pg_attribute att on att.attrelid = con.confrelid and att.attnum = k.attnum),
       case con.confdeltype when 'a' then 'NO ACTION' when 'r' then 'RESTRICT' when 'c' then 'CASCADE'
            when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT' end
from pg_constraint con
join pg_class src on src.oid = con.conrelid
join pg_class tgt on tgt.oid = con.confrelid
join pg_namespace n on n.oid = src.relnamespace
where n.nspname = 'public' and con.contype = 'f'
order by src.relname, con.conname;
SQL

"${PSQL[@]}" > "$OUT/cons.txt" <<'SQL'
select rel.relname, con.contype, con.conname, pg_get_constraintdef(con.oid)
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public' and con.contype in ('p','u','c')
order by rel.relname, con.contype, con.conname;
SQL

echo "catalog dumped to $OUT/"
