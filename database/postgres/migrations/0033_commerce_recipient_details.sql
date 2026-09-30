BEGIN;

ALTER TABLE commerce_recipients
  ADD COLUMN IF NOT EXISTS method text NOT NULL DEFAULT 'bank',
  ADD COLUMN IF NOT EXISTS institution_code text NOT NULL DEFAULT 'other',
  ADD COLUMN IF NOT EXISTS account_name text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS account_number text NOT NULL DEFAULT '';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'commerce_recipients_method_check'
  ) THEN
    ALTER TABLE commerce_recipients
      ADD CONSTRAINT commerce_recipients_method_check
      CHECK (method IN ('bank', 'momo', 'vnpay'));
  END IF;
END $$;

COMMIT;
