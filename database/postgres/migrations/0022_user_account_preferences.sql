-- 0022 — persisted client settings and the remaining onboarding preferences.
-- Keeps authentication data in Keycloak while giving every CodeMentor user one
-- extensible, product-owned settings record.

BEGIN;

ALTER TABLE learning_preferences
  ADD COLUMN interested_technologies text[] NOT NULL DEFAULT '{}',
  ADD COLUMN preferred_learning_formats text[] NOT NULL DEFAULT '{}';

CREATE TABLE user_settings (
  user_id                  uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  email_notifications      boolean NOT NULL DEFAULT true,
  workspace_notifications  boolean NOT NULL DEFAULT true,
  learning_reminders       boolean NOT NULL DEFAULT true,
  weekly_digest            boolean NOT NULL DEFAULT true,
  public_profile           boolean NOT NULL DEFAULT false,
  show_learning_progress   boolean NOT NULL DEFAULT true,
  allow_workspace_invites  boolean NOT NULL DEFAULT true,
  theme                    text NOT NULL DEFAULT 'system',
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT user_settings_theme CHECK (theme IN ('light', 'dark', 'system'))
);

CREATE TRIGGER trg_user_settings_touch BEFORE UPDATE ON user_settings
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

COMMENT ON TABLE user_settings IS
  'Per-user product settings. Passwords and authentication sessions remain in Keycloak.';

COMMIT;
