-- Workspace subscriptions: plan catalog with immutable versions, subscription snapshots, orders
-- sharing commerce_payments, coupons, entitlement adjustments and upload reservations.
-- Design: database/docs/adr/0002-workspace-subscriptions.md. Additive; no existing row changes.
BEGIN;

-- ---------------------------------------------------------------- catalog (learning-service)
CREATE TABLE workspace_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code citext NOT NULL UNIQUE CHECK (code ~ '^[a-z][a-z0-9-]{1,30}$'),
  sort_order integer NOT NULL DEFAULT 0,
  is_default boolean NOT NULL DEFAULT false,
  is_recommended boolean NOT NULL DEFAULT false,
  is_purchasable boolean NOT NULL DEFAULT true,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','hidden','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT (is_default AND (is_purchasable OR status <> 'active')))
);
-- Exactly one fallback plan; it is free and never sold.
CREATE UNIQUE INDEX workspace_plans_one_default ON workspace_plans((true)) WHERE is_default;

-- Feature flags are a closed registry: adding one is a migration, never an arbitrary JSON key.
CREATE TABLE workspace_plan_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES workspace_plans(id),
  version integer NOT NULL CHECK (version > 0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 60),
  tagline text NOT NULL DEFAULT '' CHECK (length(tagline) <= 120),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 600),
  highlights text[] NOT NULL DEFAULT '{}' CHECK (cardinality(highlights) <= 8),
  -- 0 = free; otherwise within the payment gateways' accepted range.
  monthly_price_vnd integer NOT NULL CHECK (monthly_price_vnd = 0 OR monthly_price_vnd BETWEEN 5000 AND 999999999),
  annual_price_vnd integer CHECK (annual_price_vnd IS NULL OR annual_price_vnd BETWEEN 5000 AND 999999999),
  max_owned_groups integer NOT NULL CHECK (max_owned_groups BETWEEN 0 AND 100000),
  max_members_per_group integer CHECK (max_members_per_group IS NULL OR max_members_per_group BETWEEN 2 AND 1000000),
  max_storage_bytes bigint NOT NULL CHECK (max_storage_bytes >= 0),
  max_upload_bytes bigint NOT NULL CHECK (max_upload_bytes > 0),
  monthly_ai_requests integer NOT NULL CHECK (monthly_ai_requests >= 0),
  features text[] NOT NULL DEFAULT '{}'
    CHECK (features <@ ARRAY['priority_support','advanced_assignments','detailed_analytics']::text[]),
  available_from timestamptz,
  published_at timestamptz,
  published_by uuid REFERENCES users(id),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plan_id, version),
  CHECK (max_upload_bytes <= GREATEST(max_storage_bytes, 1)),
  CHECK (annual_price_vnd IS NULL OR monthly_price_vnd > 0),
  CHECK ((status = 'published') = (published_at IS NOT NULL AND available_from IS NOT NULL))
);
CREATE UNIQUE INDEX workspace_plan_versions_one_draft ON workspace_plan_versions(plan_id) WHERE status = 'draft';
CREATE INDEX workspace_plan_versions_on_sale ON workspace_plan_versions(plan_id, version DESC) WHERE status = 'published';

CREATE FUNCTION workspace_plan_version_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status = 'published' THEN RAISE EXCEPTION 'Published plan versions are immutable'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.status = 'published' THEN RAISE EXCEPTION 'Published plan versions are immutable'; END IF;
  IF NEW.plan_id IS DISTINCT FROM OLD.plan_id OR NEW.version IS DISTINCT FROM OLD.version THEN
    RAISE EXCEPTION 'Plan version identity is immutable';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_plan_version_guard BEFORE UPDATE OR DELETE ON workspace_plan_versions
FOR EACH ROW EXECUTE FUNCTION workspace_plan_version_guard();

CREATE TABLE workspace_billing_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  grace_days integer NOT NULL DEFAULT 7 CHECK (grace_days BETWEEN 0 AND 30),
  renewal_reminder_days integer NOT NULL DEFAULT 7 CHECK (renewal_reminder_days BETWEEN 1 AND 30),
  terms_version text NOT NULL DEFAULT 'workspace-terms-2026-10' CHECK (length(terms_version) BETWEEN 1 AND 60),
  updated_by uuid REFERENCES users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO workspace_billing_settings DEFAULT VALUES;

-- -------------------------------------------------------------- coupons (learning-service)
CREATE TABLE workspace_coupons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code citext NOT NULL UNIQUE CHECK (code ~ '^[A-Za-z0-9_-]{3,32}$'),
  kind text NOT NULL CHECK (kind IN ('percent','fixed')),
  value integer NOT NULL CHECK (value > 0),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  max_redemptions integer CHECK (max_redemptions IS NULL OR max_redemptions > 0),
  per_user_limit integer NOT NULL DEFAULT 1 CHECK (per_user_limit > 0),
  plan_ids uuid[],
  billing_cycles text[] CHECK (billing_cycles IS NULL OR billing_cycles <@ ARRAY['month','year']::text[]),
  new_customers_only boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  CHECK (kind <> 'percent' OR value <= 100)
);

-- ------------------------------------------------- subscriptions and orders (learning-service)
CREATE TABLE workspace_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  plan_id uuid NOT NULL REFERENCES workspace_plans(id),
  plan_version_id uuid NOT NULL REFERENCES workspace_plan_versions(id),
  billing_cycle text NOT NULL CHECK (billing_cycle IN ('month','year')),
  -- Contract: what renewals of THIS subscription cost and grant, whatever the plan says later.
  price_vnd integer NOT NULL CHECK (price_vnd BETWEEN 5000 AND 999999999),
  plan_name text NOT NULL,
  max_owned_groups integer NOT NULL CHECK (max_owned_groups >= 0),
  max_members_per_group integer CHECK (max_members_per_group IS NULL OR max_members_per_group >= 2),
  max_storage_bytes bigint NOT NULL CHECK (max_storage_bytes >= 0),
  max_upload_bytes bigint NOT NULL CHECK (max_upload_bytes > 0),
  monthly_ai_requests integer NOT NULL CHECK (monthly_ai_requests >= 0),
  features text[] NOT NULL,
  terms_version text NOT NULL,
  snapshot jsonb NOT NULL,
  -- Lifecycle (mutable): renewal opt-out, scheduled change, end, suspension.
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  scheduled_plan_id uuid REFERENCES workspace_plans(id),
  scheduled_cycle text CHECK (scheduled_cycle IN ('month','year')),
  ended_at timestamptz,
  end_reason text CHECK (end_reason IN ('expired','upgraded','replaced','refunded','admin')),
  suspended_at timestamptz,
  suspended_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((ended_at IS NULL) = (end_reason IS NULL)),
  CHECK ((scheduled_plan_id IS NULL) = (scheduled_cycle IS NULL)),
  CHECK ((suspended_at IS NULL) = (suspended_reason IS NULL))
);
-- At most one open (not ended) base subscription per account.
CREATE UNIQUE INDEX workspace_subscriptions_one_open ON workspace_subscriptions(user_id) WHERE ended_at IS NULL;
CREATE INDEX workspace_subscriptions_user ON workspace_subscriptions(user_id, created_at DESC);

CREATE FUNCTION workspace_subscription_terms_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.user_id,NEW.plan_id,NEW.plan_version_id,NEW.billing_cycle,NEW.price_vnd,NEW.plan_name,
         NEW.max_owned_groups,NEW.max_members_per_group,NEW.max_storage_bytes,NEW.max_upload_bytes,
         NEW.monthly_ai_requests,NEW.features,NEW.terms_version,NEW.snapshot,NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.user_id,OLD.plan_id,OLD.plan_version_id,OLD.billing_cycle,OLD.price_vnd,OLD.plan_name,
         OLD.max_owned_groups,OLD.max_members_per_group,OLD.max_storage_bytes,OLD.max_upload_bytes,
         OLD.monthly_ai_requests,OLD.features,OLD.terms_version,OLD.snapshot,OLD.created_at) THEN
    RAISE EXCEPTION 'Subscription entitlements and price are immutable; record an adjustment instead';
  END IF;
  IF OLD.ended_at IS NOT NULL AND NEW.ended_at IS DISTINCT FROM OLD.ended_at THEN
    RAISE EXCEPTION 'An ended subscription cannot be reopened';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_subscription_terms_immutable BEFORE UPDATE ON workspace_subscriptions
FOR EACH ROW EXECUTE FUNCTION workspace_subscription_terms_immutable();
CREATE TRIGGER workspace_subscriptions_no_delete BEFORE DELETE ON workspace_subscriptions
FOR EACH ROW EXECUTE FUNCTION commerce_immutable();

CREATE TABLE workspace_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL REFERENCES users(id),
  kind text NOT NULL CHECK (kind IN ('new','renewal','upgrade')),
  plan_id uuid NOT NULL REFERENCES workspace_plans(id),
  plan_version_id uuid NOT NULL REFERENCES workspace_plan_versions(id),
  billing_cycle text NOT NULL CHECK (billing_cycle IN ('month','year')),
  -- renewal: the subscription extended; upgrade: the subscription replaced.
  subscription_id uuid REFERENCES workspace_subscriptions(id),
  list_price_vnd integer NOT NULL CHECK (list_price_vnd > 0),
  discount_vnd integer NOT NULL DEFAULT 0 CHECK (discount_vnd >= 0),
  credit_vnd integer NOT NULL DEFAULT 0 CHECK (credit_vnd >= 0),
  amount_vnd integer NOT NULL CHECK (amount_vnd BETWEEN 5000 AND 999999999),
  coupon_id uuid REFERENCES workspace_coupons(id),
  quote jsonb NOT NULL,
  mode text NOT NULL CHECK (mode IN ('mock','sandbox')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed','cancelled','expired','review','refunded')),
  result_subscription_id uuid REFERENCES workspace_subscriptions(id),
  paid_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '20 minutes',
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (amount_vnd = list_price_vnd - discount_vnd - credit_vnd),
  CHECK ((kind = 'new') = (subscription_id IS NULL)),
  CHECK ((status = 'paid') = (paid_at IS NOT NULL AND result_subscription_id IS NOT NULL) OR status IN ('review','refunded'))
);
-- One open checkout per account: concurrent purchases resolve to the same order or a conflict.
CREATE UNIQUE INDEX workspace_orders_one_pending ON workspace_orders(buyer_id) WHERE status = 'pending';
CREATE INDEX workspace_orders_buyer ON workspace_orders(buyer_id, created_at DESC);
CREATE INDEX workspace_orders_status ON workspace_orders(status, created_at DESC);

CREATE FUNCTION workspace_order_terms_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.buyer_id,NEW.kind,NEW.plan_id,NEW.plan_version_id,NEW.billing_cycle,NEW.subscription_id,
         NEW.list_price_vnd,NEW.discount_vnd,NEW.credit_vnd,NEW.amount_vnd,NEW.coupon_id,NEW.quote,NEW.mode,NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.buyer_id,OLD.kind,OLD.plan_id,OLD.plan_version_id,OLD.billing_cycle,OLD.subscription_id,
         OLD.list_price_vnd,OLD.discount_vnd,OLD.credit_vnd,OLD.amount_vnd,OLD.coupon_id,OLD.quote,OLD.mode,OLD.created_at) THEN
    RAISE EXCEPTION 'Workspace order pricing terms are immutable';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_order_terms_immutable BEFORE UPDATE ON workspace_orders
FOR EACH ROW EXECUTE FUNCTION workspace_order_terms_immutable();

CREATE TABLE workspace_subscription_terms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES workspace_subscriptions(id),
  order_id uuid NOT NULL UNIQUE REFERENCES workspace_orders(id),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);
CREATE INDEX workspace_subscription_terms_sub ON workspace_subscription_terms(subscription_id, ends_at DESC);
CREATE TRIGGER workspace_subscription_terms_history BEFORE UPDATE OR DELETE ON workspace_subscription_terms
FOR EACH ROW EXECUTE FUNCTION commerce_immutable();

-- Paid periods of one account never overlap; an ended subscription's term is cut at ended_at.
CREATE FUNCTION workspace_terms_no_overlap() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE owner uuid;
BEGIN
  SELECT user_id INTO owner FROM workspace_subscriptions WHERE id = NEW.subscription_id;
  PERFORM pg_advisory_xact_lock(hashtextextended('ws-billing:' || owner::text, 0));
  IF EXISTS (
    SELECT 1 FROM workspace_subscription_terms t
    JOIN workspace_subscriptions s ON s.id = t.subscription_id
    WHERE s.user_id = owner AND t.id <> NEW.id
      AND t.starts_at < NEW.ends_at
      AND LEAST(t.ends_at, COALESCE(s.ended_at, 'infinity')) > NEW.starts_at
  ) THEN
    RAISE EXCEPTION 'Workspace subscription terms overlap for user %', owner;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_terms_no_overlap BEFORE INSERT ON workspace_subscription_terms
FOR EACH ROW EXECUTE FUNCTION workspace_terms_no_overlap();

CREATE TABLE workspace_coupon_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id uuid NOT NULL REFERENCES workspace_coupons(id),
  order_id uuid NOT NULL UNIQUE REFERENCES workspace_orders(id),
  user_id uuid NOT NULL REFERENCES users(id),
  status text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved','redeemed','released')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX workspace_coupon_redemptions_coupon ON workspace_coupon_redemptions(coupon_id, status);
CREATE INDEX workspace_coupon_redemptions_user ON workspace_coupon_redemptions(user_id, coupon_id);

-- Exceptional grants, added on top of the snapshot. Never edits a purchased subscription.
CREATE TABLE workspace_entitlement_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  entitlement text NOT NULL CHECK (entitlement IN ('max_owned_groups','max_members_per_group','max_storage_bytes','max_upload_bytes','monthly_ai_requests')),
  amount bigint NOT NULL CHECK (amount > 0),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 500),
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  revoked_by uuid REFERENCES users(id),
  CHECK (ends_at > starts_at),
  CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);
CREATE INDEX workspace_entitlement_adjustments_user ON workspace_entitlement_adjustments(user_id, ends_at);

-- ------------------------------------------------- shared payment rows and ledger links
ALTER TABLE commerce_payments ALTER COLUMN order_id DROP NOT NULL;
ALTER TABLE commerce_payments ADD COLUMN workspace_order_id uuid UNIQUE REFERENCES workspace_orders(id);
ALTER TABLE commerce_payments ADD CONSTRAINT commerce_payments_one_order
  CHECK (num_nonnulls(order_id, workspace_order_id) = 1);
ALTER TABLE commerce_journals ADD COLUMN workspace_order_id uuid REFERENCES workspace_orders(id);

-- ---------------------------------------------------- upload reservations (workspace-service)
CREATE TABLE workspace_storage_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES users(id),
  group_id uuid NOT NULL REFERENCES study_groups(id) ON DELETE CASCADE,
  object_key text NOT NULL UNIQUE,
  bytes bigint NOT NULL CHECK (bytes > 0),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at > created_at)
);
CREATE INDEX workspace_storage_reservations_owner ON workspace_storage_reservations(owner_id, expires_at);
CREATE INDEX IF NOT EXISTS study_groups_owner ON study_groups(owner_id);  -- owned-group quota

-- ------------------------------------------------------------------ read contract
-- The entitlements in force for an account right now. Paid while a term covers now, or within
-- grace after a term the owner did not cancel; otherwise the default plan's version on sale.
-- Active adjustments add to every finite limit (NULL = unlimited stays unlimited).
CREATE FUNCTION workspace_effective_entitlements(p_user uuid)
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
      o.max_storage_bytes, o.max_upload_bytes, o.monthly_ai_requests, o.features, o.paid_through,
      o.paid_through + make_interval(days => (SELECT grace_days FROM settings)) AS grace_ends_at
    FROM open_sub o JOIN workspace_plans p ON p.id = o.plan_id
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

-- ------------------------------------------------------------------- initial catalog
INSERT INTO workspace_plans (code, sort_order, is_default, is_recommended, is_purchasable) VALUES
  ('free', 0, true,  false, false),
  ('plus', 1, false, true,  true),
  ('pro',  2, false, false, true),
  ('team', 3, false, false, true);

INSERT INTO workspace_plan_versions (plan_id, version, status, name, tagline, description, highlights,
  monthly_price_vnd, annual_price_vnd, max_owned_groups, max_members_per_group, max_storage_bytes,
  max_upload_bytes, monthly_ai_requests, features, available_from, published_at)
SELECT p.id, 1, 'published', v.name, v.tagline, v.description, v.highlights, v.monthly, v.annual,
  v.groups, v.members, v.storage, v.upload, v.ai, v.features, now(), now()
FROM (VALUES
  ('free', 'Free', 'Get started', 'For trying study groups with a few classmates.',
   ARRAY[]::text[], 0, NULL::integer,
   1, 10, 104857600::bigint, 10485760::bigint, 30, ARRAY[]::text[]),
  ('plus', 'Plus', 'Learn together', 'For study groups that meet every week.',
   ARRAY['Best for weekly study groups'], 99000, 990000,
   5, 50, 2147483648::bigint, 104857600::bigint, 200, ARRAY[]::text[]),
  ('pro', 'Pro', 'Grow your community', 'For mentors running several active communities.',
   ARRAY['Unlimited members under fair use'], 199000, 1990000,
   20, NULL, 21474836480::bigint, 262144000::bigint, 500, ARRAY['priority_support']),
  ('team', 'Team', 'Collaborate at scale', 'For schools and teams with many classes.',
   ARRAY['Unlimited members under fair use','Highest AI allowance'], 499000, 4990000,
   100, NULL, 107374182400::bigint, 524288000::bigint, 1500, ARRAY['priority_support'])
) AS v(code, name, tagline, description, highlights, monthly, annual, groups, members, storage, upload, ai, features)
JOIN workspace_plans p ON p.code = v.code;

COMMIT;
