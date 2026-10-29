-- Workspace subscriptions, part 2: what happens to groups when an owner stays above their plan,
-- and the two group features that now ship (advanced assignments, detailed analytics).
-- Design: database/docs/adr/0002-workspace-subscriptions.md ("Over-limit groups", "Features").
BEGIN;

-- ----------------------------------------------------- over-limit policy (learning-service)
-- Days counted from the moment an owner is first seen above their limits:
--   [0, notice)                    warning only, everything works
--   [notice, notice + read_only)   groups above the limits are read-only
--   [notice + read_only, ...)      those groups are hidden from members; nothing is deleted
ALTER TABLE workspace_billing_settings
  ADD COLUMN overage_notice_days integer NOT NULL DEFAULT 7 CHECK (overage_notice_days BETWEEN 0 AND 60),
  ADD COLUMN overage_read_only_days integer NOT NULL DEFAULT 30 CHECK (overage_read_only_days BETWEEN 1 AND 365);

-- ------------------------------------------------------ over-limit state (workspace-service)
-- One row while an owner is above any limit; deleted as soon as they are back within it.
-- Written by the workspace-service sweep, read by billing reminders.
CREATE TABLE workspace_owner_overage (
  owner_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  over_since timestamptz NOT NULL DEFAULT now(),
  checked_at timestamptz NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------- read contract, revised
-- A paid snapshot keeps its limits and price, but features added to the plan later reach
-- existing subscribers too: features only ever add, so the union is safe.
CREATE OR REPLACE FUNCTION workspace_effective_entitlements(p_user uuid)
RETURNS TABLE (
  source text,
  subscription_id uuid,
  plan_id uuid,
  plan_version_id uuid,
  plan_code text,
  plan_name text,
  max_owned_groups integer,
  max_members_per_group integer,
  max_storage_bytes bigint,
  max_upload_bytes bigint,
  monthly_ai_requests integer,
  features text[],
  paid_through timestamptz,
  grace_ends_at timestamptz
) LANGUAGE sql STABLE AS $$
  WITH settings AS (SELECT grace_days FROM workspace_billing_settings),
  open_sub AS (
    SELECT s.*, (SELECT max(t.ends_at) FROM workspace_subscription_terms t WHERE t.subscription_id = s.id) AS paid_through,
      EXISTS (SELECT 1 FROM workspace_subscription_terms t WHERE t.subscription_id = s.id
              AND t.starts_at <= now() AND t.ends_at > now()) AS covered
    FROM workspace_subscriptions s
    WHERE s.user_id = p_user AND s.ended_at IS NULL AND s.suspended_at IS NULL
  ),
  paid AS (
    SELECT CASE WHEN o.covered THEN 'paid' ELSE 'grace' END AS source, o.id AS subscription_id, o.plan_id,
      o.plan_version_id, p.code::text AS plan_code, o.plan_name, o.max_owned_groups, o.max_members_per_group,
      o.max_storage_bytes, o.max_upload_bytes, o.monthly_ai_requests,
      ARRAY(SELECT DISTINCT f FROM unnest(o.features || COALESCE(cur.features, '{}')) f ORDER BY f) AS features,
      o.paid_through,
      o.paid_through + make_interval(days => (SELECT grace_days FROM settings)) AS grace_ends_at
    FROM open_sub o JOIN workspace_plans p ON p.id = o.plan_id
    LEFT JOIN LATERAL (
      SELECT v.features FROM workspace_plan_versions v WHERE v.plan_id = o.plan_id AND v.status = 'published'
        AND v.available_from <= now() ORDER BY v.version DESC LIMIT 1
    ) cur ON true
    WHERE o.covered OR (NOT o.cancel_at_period_end AND o.paid_through <= now()
      AND now() < o.paid_through + make_interval(days => (SELECT grace_days FROM settings)))
  ),
  free AS (
    SELECT 'free'::text AS source, NULL::uuid AS subscription_id, p.id AS plan_id, v.id AS plan_version_id,
      p.code::text AS plan_code, v.name AS plan_name, v.max_owned_groups, v.max_members_per_group,
      v.max_storage_bytes, v.max_upload_bytes, v.monthly_ai_requests, v.features,
      NULL::timestamptz AS paid_through, NULL::timestamptz AS grace_ends_at
    FROM workspace_plans p
    JOIN LATERAL (
      SELECT * FROM workspace_plan_versions v WHERE v.plan_id = p.id AND v.status = 'published'
        AND v.available_from <= now() ORDER BY v.version DESC LIMIT 1
    ) v ON true
    WHERE p.is_default
  ),
  base AS (SELECT * FROM paid UNION ALL SELECT * FROM free WHERE NOT EXISTS (SELECT 1 FROM paid)),
  adj AS (
    SELECT entitlement, sum(amount) AS amount FROM workspace_entitlement_adjustments
    WHERE user_id = p_user AND revoked_at IS NULL AND starts_at <= now() AND ends_at > now()
    GROUP BY entitlement
  )
  SELECT b.source, b.subscription_id, b.plan_id, b.plan_version_id, b.plan_code, b.plan_name,
    (b.max_owned_groups + COALESCE((SELECT amount FROM adj WHERE entitlement = 'max_owned_groups'), 0))::integer,
    (b.max_members_per_group + COALESCE((SELECT amount FROM adj WHERE entitlement = 'max_members_per_group'), 0))::integer,
    b.max_storage_bytes + COALESCE((SELECT amount FROM adj WHERE entitlement = 'max_storage_bytes'), 0)::bigint,
    b.max_upload_bytes + COALESCE((SELECT amount FROM adj WHERE entitlement = 'max_upload_bytes'), 0)::bigint,
    (b.monthly_ai_requests + COALESCE((SELECT amount FROM adj WHERE entitlement = 'monthly_ai_requests'), 0))::integer,
    b.features, b.paid_through, b.grace_ends_at
  FROM base b
$$;

-- ------------------------------------------------------------------- catalog revision
-- Paid plans gain the two group features. Published versions are immutable, so each paid plan
-- gets a new version with the original prices and limits; an unpublished draft is discarded.
DELETE FROM workspace_plan_versions v USING workspace_plans p
WHERE v.plan_id = p.id AND p.code IN ('plus','pro','team') AND v.status = 'draft';

INSERT INTO workspace_plan_versions (plan_id, version, status, name, tagline, description, highlights,
  monthly_price_vnd, annual_price_vnd, max_owned_groups, max_members_per_group, max_storage_bytes,
  max_upload_bytes, monthly_ai_requests, features, available_from, published_at)
SELECT p.id, (SELECT max(version) + 1 FROM workspace_plan_versions WHERE plan_id = p.id), 'published',
  v.name, v.tagline, v.description, v.highlights, v.monthly, v.annual,
  v.groups, v.members, v.storage, v.upload, v.ai, v.features, now(), now()
FROM (VALUES
  ('plus', 'Plus', 'Học cùng nhau', 'Cho các nhóm học tập sinh hoạt hằng tuần.',
   ARRAY['Phù hợp nhóm học hằng tuần','Giao bài có hạn nộp cho từng thành viên','Thống kê tiến độ từng thành viên'],
   99000, 990000, 5, 50, 2147483648::bigint, 104857600::bigint, 200,
   ARRAY['advanced_assignments','detailed_analytics']),
  ('pro', 'Pro', 'Phát triển cộng đồng', 'Cho người hướng dẫn quản lý nhiều cộng đồng học tập.',
   ARRAY['Không giới hạn thành viên (sử dụng hợp lý)','Hỗ trợ ưu tiên'],
   199000, 1990000, 20, NULL, 21474836480::bigint, 262144000::bigint, 500,
   ARRAY['advanced_assignments','detailed_analytics','priority_support']),
  ('team', 'Team', 'Cộng tác quy mô lớn', 'Cho trường học và đội nhóm có nhiều lớp.',
   ARRAY['Không giới hạn thành viên (sử dụng hợp lý)','Hạn mức AI cao nhất','Hỗ trợ ưu tiên'],
   499000, 4990000, 100, NULL, 107374182400::bigint, 524288000::bigint, 1500,
   ARRAY['advanced_assignments','detailed_analytics','priority_support'])
) AS v(code, name, tagline, description, highlights, monthly, annual, groups, members, storage, upload, ai, features)
JOIN workspace_plans p ON p.code = v.code;

COMMIT;
