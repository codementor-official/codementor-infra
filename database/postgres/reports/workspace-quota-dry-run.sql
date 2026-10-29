-- Report: how existing owners compare with the Free Workspace limits. Run after 0042 (it reads
-- the plan catalog). Only temporary tables are created and the transaction is rolled back.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/postgres/reports/workspace-quota-dry-run.sql
BEGIN;

CREATE TEMP TABLE free_limits ON COMMIT DROP AS
SELECT
  COALESCE((SELECT v.max_owned_groups FROM workspace_plan_versions v JOIN workspace_plans p ON p.id = v.plan_id
            WHERE p.is_default AND v.status = 'published' ORDER BY v.version DESC LIMIT 1), 1) AS max_groups,
  COALESCE((SELECT v.max_members_per_group FROM workspace_plan_versions v JOIN workspace_plans p ON p.id = v.plan_id
            WHERE p.is_default AND v.status = 'published' ORDER BY v.version DESC LIMIT 1), 10) AS max_members,
  COALESCE((SELECT v.max_storage_bytes FROM workspace_plan_versions v JOIN workspace_plans p ON p.id = v.plan_id
            WHERE p.is_default AND v.status = 'published' ORDER BY v.version DESC LIMIT 1), 104857600) AS max_storage;
\echo 'Free limits used for this report'
TABLE free_limits;

CREATE TEMP TABLE owner_usage ON COMMIT DROP AS
SELECT g.owner_id,
  count(*) AS owned_groups,
  count(*) FILTER (WHERE g.status = 'archived') AS archived_groups,
  max(g.member_count) AS largest_group_members,
  COALESCE(sum(d.bytes), 0)::bigint AS stored_bytes
FROM study_groups g
LEFT JOIN LATERAL (
  SELECT sum(size_bytes) AS bytes FROM group_documents WHERE group_id = g.id
) d ON true
GROUP BY g.owner_id;

\echo 'Totals'
SELECT (SELECT count(*) FROM users) AS accounts,
  count(*) AS owners,
  sum(owned_groups) AS groups,
  pg_size_pretty(sum(stored_bytes)) AS stored,
  count(*) FILTER (WHERE owned_groups > l.max_groups) AS over_group_limit,
  count(*) FILTER (WHERE largest_group_members > l.max_members) AS over_member_limit,
  count(*) FILTER (WHERE stored_bytes > l.max_storage) AS over_storage_limit
FROM owner_usage, free_limits l
GROUP BY l.max_groups, l.max_members, l.max_storage;

\echo 'Owners above at least one Free limit (they keep everything; new usage is blocked)'
SELECT u.email, o.owned_groups, o.archived_groups, o.largest_group_members,
  pg_size_pretty(o.stored_bytes) AS stored
FROM owner_usage o JOIN users u ON u.id = o.owner_id, free_limits l
WHERE o.owned_groups > l.max_groups OR o.largest_group_members > l.max_members OR o.stored_bytes > l.max_storage
ORDER BY o.stored_bytes DESC, o.owned_groups DESC;

\echo 'Documents with an unknown size (counted as 0 bytes; need manual review)'
SELECT g.slug, count(*) AS documents
FROM group_documents d JOIN study_groups g ON g.id = d.group_id
WHERE d.storage_key IS NOT NULL AND d.size_bytes IS NULL
GROUP BY g.slug ORDER BY documents DESC;

ROLLBACK;
