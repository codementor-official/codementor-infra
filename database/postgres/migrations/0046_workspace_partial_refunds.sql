-- Refunds give back the unused share of a term instead of always the whole order (ADR 0002
-- "Refunds"). `refunded_vnd` records what was actually returned; revenue is amount minus it.
-- Orders refunded before this migration were refunded in full.
BEGIN;

ALTER TABLE workspace_orders ADD COLUMN IF NOT EXISTS refunded_vnd integer;

UPDATE workspace_orders SET refunded_vnd = amount_vnd WHERE status = 'refunded' AND refunded_vnd IS NULL;

ALTER TABLE workspace_orders ADD CONSTRAINT workspace_orders_refunded_vnd_check CHECK (
  (status = 'refunded') = (refunded_vnd IS NOT NULL)
  AND (refunded_vnd IS NULL OR refunded_vnd BETWEEN 1 AND amount_vnd)
);

COMMENT ON COLUMN workspace_orders.refunded_vnd IS
  'Amount returned to the buyer, set with status refunded. Policy: the unused share of the order''s term; an administrator may record a different amount with a reason.';

COMMIT;
