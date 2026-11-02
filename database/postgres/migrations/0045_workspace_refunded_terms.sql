-- Refunds: a term whose order was refunded no longer counts. Terms stay immutable (history);
-- every read of "what is paid" goes through workspace_paid_terms instead of the table.
-- Effect of a refund (decided by learning-service, ADR 0002 "Refunds"):
--   term not started yet  -> that term disappears; the current one is untouched
--   term running          -> the subscription ends now (reason `refunded`)
--   term already over     -> money only
BEGIN;

CREATE VIEW workspace_paid_terms AS
SELECT t.* FROM workspace_subscription_terms t
JOIN workspace_orders o ON o.id = t.order_id
WHERE o.status <> 'refunded';

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
    SELECT s.*, (SELECT max(t.ends_at) FROM workspace_paid_terms t WHERE t.subscription_id = s.id) AS paid_through,
      EXISTS (SELECT 1 FROM workspace_paid_terms t WHERE t.subscription_id = s.id
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

-- A refunded term frees its period: a new renewal may take it.
CREATE OR REPLACE FUNCTION workspace_terms_no_overlap() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE owner uuid;
BEGIN
  SELECT user_id INTO owner FROM workspace_subscriptions WHERE id = NEW.subscription_id;
  PERFORM pg_advisory_xact_lock(hashtextextended('ws-billing:' || owner::text, 0));
  IF EXISTS (
    SELECT 1 FROM workspace_paid_terms t
    JOIN workspace_subscriptions s ON s.id = t.subscription_id
    WHERE s.user_id = owner AND t.id <> NEW.id
      AND t.starts_at < NEW.ends_at
      AND LEAST(t.ends_at, COALESCE(s.ended_at, 'infinity')) > NEW.starts_at
  ) THEN
    RAISE EXCEPTION 'Workspace subscription terms overlap for user %', owner;
  END IF;
  RETURN NEW;
END $$;

COMMIT;
