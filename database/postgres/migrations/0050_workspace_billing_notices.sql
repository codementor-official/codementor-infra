-- Administrators switch each workspace billing notice (purchase, payment review, refund, renewal
-- reminder, grace, overage, admin alerts) between in-app + email, in-app only, or off.
-- Keys never set mean in-app + email, so existing behaviour is unchanged.
BEGIN;

ALTER TABLE workspace_billing_settings ADD COLUMN IF NOT EXISTS notices jsonb NOT NULL DEFAULT '{}'::jsonb
  CHECK (jsonb_typeof(notices) = 'object');

COMMENT ON COLUMN workspace_billing_settings.notices IS
  'Billing notice key -> all | app | off. Missing key = all. Read and validated by learning-service.';

COMMIT;
