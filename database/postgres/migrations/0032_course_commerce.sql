-- Learning-service owns commerce. Apply once using the migration runner, never prisma migrate.
BEGIN;
CREATE TABLE commerce_policy (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  instructor_bps integer NOT NULL DEFAULT 8000 CHECK (instructor_bps BETWEEN 0 AND 10000),
  hold_days integer NOT NULL DEFAULT 7 CHECK (hold_days BETWEEN 0 AND 90),
  minimum_withdrawal integer NOT NULL DEFAULT 100000 CHECK (minimum_withdrawal BETWEEN 1000 AND 1000000000),
  approval_required boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO commerce_policy DEFAULT VALUES;
CREATE TABLE course_prices (
  course_id uuid PRIMARY KEY REFERENCES courses(id) ON DELETE CASCADE,
  price_vnd integer NOT NULL DEFAULT 0 CHECK (price_vnd BETWEEN 0 AND 1000000000),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE commerce_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL REFERENCES users(id),
  course_id uuid NOT NULL REFERENCES courses(id),
  instructor_id uuid NOT NULL REFERENCES users(id),
  course_title text NOT NULL,
  amount integer NOT NULL CHECK (amount > 0),
  currency text NOT NULL DEFAULT 'VND' CHECK (currency = 'VND'),
  instructor_bps integer NOT NULL CHECK (instructor_bps BETWEEN 0 AND 10000),
  instructor_amount integer NOT NULL CHECK (instructor_amount >= 0),
  platform_amount integer NOT NULL CHECK (platform_amount >= 0),
  hold_days integer NOT NULL CHECK (hold_days BETWEEN 0 AND 90),
  mode text NOT NULL CHECK (mode IN ('mock','sandbox')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed','cancelled','expired','review','refunded')),
  income_state text NOT NULL DEFAULT 'none' CHECK (income_state IN ('none','pending','available','refund_held','refunded')),
  settled_at timestamptz,
  available_at timestamptz,
  fee_amount integer CHECK (fee_amount >= 0),
  fee_source text NOT NULL DEFAULT 'unknown' CHECK (fee_source IN ('unknown','simulated','provider')),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '20 minutes',
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (instructor_amount + platform_amount = amount)
);
CREATE UNIQUE INDEX commerce_one_open_order ON commerce_orders(buyer_id, course_id) WHERE status = 'pending';
CREATE INDEX commerce_orders_buyer ON commerce_orders(buyer_id, created_at DESC);
CREATE INDEX commerce_orders_instructor ON commerce_orders(instructor_id, created_at DESC);
CREATE TABLE commerce_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL UNIQUE REFERENCES commerce_orders(id),
  provider text NOT NULL CHECK (provider IN ('mock','vnpay','momo')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','succeeded','failed','cancelled','unknown')),
  provider_ref text,
  checkout_url text,
  create_started_at timestamptz,
  provider_date text,
  reconciled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_ref)
);
CREATE TABLE course_access_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  course_id uuid NOT NULL REFERENCES courses(id),
  source text NOT NULL CHECK (source IN ('legacy','free','purchase','manual')),
  order_id uuid UNIQUE REFERENCES commerce_orders(id),
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((source = 'purchase') = (order_id IS NOT NULL))
);
CREATE UNIQUE INDEX course_access_independent ON course_access_grants(user_id,course_id,source) WHERE source <> 'purchase';
CREATE INDEX course_access_active ON course_access_grants(user_id,course_id) WHERE revoked_at IS NULL;
-- Include dropped enrollments: a pre-existing right is not lost by leaving a course.
INSERT INTO course_access_grants(user_id,course_id,source)
SELECT user_id,course_id,'legacy' FROM course_enrollments;

CREATE TABLE commerce_recipients (
  user_id uuid PRIMARY KEY REFERENCES users(id),
  label text NOT NULL CHECK (length(label) BETWEEN 1 AND 100),
  test_reference text NOT NULL CHECK (test_reference ~ '^TEST-[A-Za-z0-9-]{4,40}$'),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE commerce_withdrawals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instructor_id uuid NOT NULL REFERENCES users(id),
  amount integer NOT NULL CHECK (amount > 0),
  idempotency_key uuid NOT NULL,
  recipient_snapshot jsonb NOT NULL,
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','processing','pending','unknown','succeeded','failed','rejected')),
  scenario text NOT NULL DEFAULT 'success' CHECK (scenario IN ('success','failure','pending','timeout')),
  reason text,
  decided_by uuid REFERENCES users(id),
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(instructor_id,idempotency_key)
);
CREATE TABLE commerce_refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL UNIQUE REFERENCES commerce_orders(id),
  amount integer NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','unknown','succeeded','failed')),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 1000),
  requested_by uuid NOT NULL REFERENCES users(id),
  held_amount integer NOT NULL CHECK (held_amount >= 0),
  debt_amount integer NOT NULL CHECK (debt_amount >= 0),
  from_account text NOT NULL CHECK (from_account IN ('pending','available')),
  provider_ref text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE commerce_journals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  order_id uuid REFERENCES commerce_orders(id),
  withdrawal_id uuid REFERENCES commerce_withdrawals(id),
  refund_id uuid REFERENCES commerce_refunds(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE commerce_entries (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  journal_id uuid NOT NULL REFERENCES commerce_journals(id),
  owner_id uuid REFERENCES users(id),
  account text NOT NULL CHECK (account IN ('clearing','platform','pending','available','reserved','paid','refund_held','debt','fees')),
  amount bigint NOT NULL CHECK (amount <> 0)
);
CREATE INDEX commerce_balances ON commerce_entries(owner_id,account);
CREATE FUNCTION commerce_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Commerce journal history is immutable; write a compensating entry'; END $$;
CREATE TRIGGER commerce_entries_immutable BEFORE UPDATE OR DELETE ON commerce_entries FOR EACH ROW EXECUTE FUNCTION commerce_immutable();
CREATE TRIGGER commerce_journals_immutable BEFORE UPDATE OR DELETE ON commerce_journals FOR EACH ROW EXECUTE FUNCTION commerce_immutable();
CREATE FUNCTION commerce_balanced() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target uuid;
BEGIN
  IF TG_TABLE_NAME = 'commerce_journals' THEN target := NEW.id; ELSE target := NEW.journal_id; END IF;
  IF (SELECT count(*) < 2 OR COALESCE(sum(amount),0) <> 0 FROM commerce_entries WHERE journal_id=target) THEN
    RAISE EXCEPTION 'Unbalanced commerce journal %', target;
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER commerce_journal_balanced AFTER INSERT ON commerce_journals DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION commerce_balanced();
CREATE CONSTRAINT TRIGGER commerce_entries_balanced AFTER INSERT ON commerce_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION commerce_balanced();
CREATE TABLE commerce_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES users(id),
  action text NOT NULL,
  entity_id uuid,
  details jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER commerce_audit_immutable BEFORE UPDATE OR DELETE ON commerce_audit FOR EACH ROW EXECUTE FUNCTION commerce_immutable();
CREATE TABLE commerce_provider_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES commerce_payments(id),
  fingerprint text NOT NULL UNIQUE,
  result text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMIT;
