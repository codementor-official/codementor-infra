-- Additive and independent of 0037; no financial state is changed.
BEGIN;
CREATE TABLE IF NOT EXISTS commerce_provider_query_leases (
  payment_id uuid PRIMARY KEY REFERENCES commerce_payments(id) ON DELETE CASCADE,
  next_query_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS commerce_provider_query_leases_next_idx
  ON commerce_provider_query_leases(next_query_at);
COMMIT;
