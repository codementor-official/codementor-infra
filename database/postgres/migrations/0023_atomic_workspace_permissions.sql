-- Replace aggregate Workspace permissions with atomic permissions.
-- Existing grants and member overrides keep their intent through enum-value renames.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'group_permission' AND e.enumlabel = 'manage_doc'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'group_permission' AND e.enumlabel = 'edit_doc'
  ) THEN
    EXECUTE 'ALTER TYPE group_permission RENAME VALUE ''manage_doc'' TO ''edit_doc''';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'group_permission' AND e.enumlabel = 'manage_exercise'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'group_permission' AND e.enumlabel = 'delete_exercise'
  ) THEN
    EXECUTE 'ALTER TYPE group_permission RENAME VALUE ''manage_exercise'' TO ''delete_exercise''';
  END IF;
END
$$;

ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'view_doc';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'edit_own_doc';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'delete_own_doc';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'edit_doc';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'approve_doc';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'view_exercise';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'edit_own_exercise';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'delete_own_exercise';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'delete_exercise';
ALTER TYPE group_permission ADD VALUE IF NOT EXISTS 'assign_exercise';
