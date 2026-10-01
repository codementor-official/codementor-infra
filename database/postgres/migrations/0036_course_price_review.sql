BEGIN;

ALTER TABLE course_prices
  ADD COLUMN IF NOT EXISTS pending_price_vnd INTEGER,
  ADD COLUMN IF NOT EXISTS pending_price_requested_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'course_prices_pending_price_check'
  ) THEN
    ALTER TABLE course_prices
      ADD CONSTRAINT course_prices_pending_price_check
      CHECK (pending_price_vnd IS NULL OR pending_price_vnd BETWEEN 0 AND 1000000000);
  END IF;
END $$;

COMMIT;
