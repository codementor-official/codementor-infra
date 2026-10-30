-- Workspace coupons get a purpose an administrator can read later ("ưu đãi ra mắt", "sinh viên"),
-- and their editable terms are tracked. Additive.
BEGIN;

ALTER TABLE workspace_coupons
  ADD COLUMN description text NOT NULL DEFAULT '' CHECK (length(description) <= 200),
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

COMMIT;
