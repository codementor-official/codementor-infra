-- Additive consistency migration. Review/backup before applying to deployed databases.
BEGIN;
ALTER TABLE course_prices ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;
ALTER TABLE course_prices ADD COLUMN IF NOT EXISTS pending_config_id uuid;
UPDATE course_prices SET pending_config_id=gen_random_uuid()
WHERE pending_price_vnd IS NOT NULL AND pending_config_id IS NULL;
ALTER TABLE course_promotion_requests ADD COLUMN IF NOT EXISTS base_price_version integer NOT NULL DEFAULT 1;
ALTER TABLE course_promotion_requests ADD COLUMN IF NOT EXISTS price_config_id uuid;
ALTER TABLE course_promotion_requests ADD COLUMN IF NOT EXISTS base_price_vnd integer;
UPDATE course_promotion_requests r SET base_price_vnd=p.price_vnd
FROM course_prices p WHERE p.course_id=r.course_id AND r.base_price_vnd IS NULL;
-- Legacy requests are based on the published price, not silently paired to a draft.
ALTER TABLE commerce_orders ADD COLUMN IF NOT EXISTS pricing_snapshot jsonb;
CREATE OR REPLACE FUNCTION commerce_order_terms_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.buyer_id,NEW.course_id,NEW.instructor_id,NEW.amount,NEW.instructor_bps,NEW.instructor_amount,NEW.platform_amount,NEW.mode,NEW.hold_days,NEW.pricing_snapshot)
    IS DISTINCT FROM ROW(OLD.buyer_id,OLD.course_id,OLD.instructor_id,OLD.amount,OLD.instructor_bps,OLD.instructor_amount,OLD.platform_amount,OLD.mode,OLD.hold_days,OLD.pricing_snapshot) THEN
    RAISE EXCEPTION 'Order pricing and revenue terms are immutable';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS commerce_order_terms_immutable ON commerce_orders;
CREATE TRIGGER commerce_order_terms_immutable BEFORE UPDATE ON commerce_orders
FOR EACH ROW EXECUTE FUNCTION commerce_order_terms_immutable();
-- Historical original prices cannot be reconstructed honestly; retain NULL on old orders.
CREATE TABLE IF NOT EXISTS commerce_reconciliation_issues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid REFERENCES commerce_payments(id),
  provider text NOT NULL CHECK(provider IN ('mock','vnpay','momo')),
  kind text NOT NULL,
  fingerprint text NOT NULL,
  details jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider,fingerprint,kind)
);
CREATE INDEX IF NOT EXISTS commerce_reconciliation_issues_payment ON commerce_reconciliation_issues(payment_id,created_at DESC);
DROP TRIGGER IF EXISTS commerce_reconciliation_issues_immutable ON commerce_reconciliation_issues;
CREATE TRIGGER commerce_reconciliation_issues_immutable BEFORE UPDATE OR DELETE ON commerce_reconciliation_issues
FOR EACH ROW EXECUTE FUNCTION commerce_immutable();
COMMIT;
