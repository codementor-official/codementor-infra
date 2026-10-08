-- Additive, idempotent. NULL preserves historical day-based policy/order snapshots.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE commerce_policy ADD COLUMN IF NOT EXISTS hold_minutes integer
  CHECK (hold_minutes BETWEEN 0 AND 129600);
ALTER TABLE commerce_orders ADD COLUMN IF NOT EXISTS hold_minutes integer
  CHECK (hold_minutes BETWEEN 0 AND 129600);
COMMIT;
