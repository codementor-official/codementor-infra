-- 0002 — users, cached user stats, personalisation survey.
-- The frontend has no user type; fields were reassembled from profile-management-page.tsx,
-- GroupMember and the auth screens. See docs/00-frontend-review.md §2.5.

BEGIN;

CREATE TABLE users (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email             citext NOT NULL UNIQUE,
  password_hash     text,                       -- null while only OAuth is linked
  handle            citext UNIQUE,              -- profile "handle" (@giasi)
  display_name      text   NOT NULL,
  bio               text,
  avatar_url        text,
  website_url       text,
  github_handle     text,
  role              platform_role  NOT NULL DEFAULT 'learner',
  status            account_status NOT NULL DEFAULT 'active',
  locale            text NOT NULL DEFAULT 'vi',
  timezone          text NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
  email_verified_at timestamptz,
  last_active_at    timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT users_display_name_not_blank CHECK (btrim(display_name) <> ''),
  -- handles appear in URLs; keep them mechanically safe
  CONSTRAINT users_handle_format CHECK (handle IS NULL OR handle ~ '^[a-z0-9](?:[a-z0-9_-]{1,28}[a-z0-9])$')
);

CREATE TRIGGER trg_users_touch BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

COMMENT ON TABLE users IS 'Platform accounts. Retired accounts are status=deleted, never hard-deleted, so authored content and submissions keep a valid author.';

-- ---------------------------------------------------------------------------
-- Cached aggregates. Split from users because these are written on every accepted
-- submission while users is read-hot and rarely written.
-- Source of truth: submissions + exercise_progress. Never written directly by the app.
-- ---------------------------------------------------------------------------
CREATE TABLE user_stats (
  user_id             uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  xp                  integer NOT NULL DEFAULT 0 CHECK (xp >= 0),
  solved_count        integer NOT NULL DEFAULT 0 CHECK (solved_count >= 0),
  current_streak_days integer NOT NULL DEFAULT 0 CHECK (current_streak_days >= 0),
  longest_streak_days integer NOT NULL DEFAULT 0 CHECK (longest_streak_days >= 0),
  last_solved_on      date,
  updated_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT user_stats_streak_ordering CHECK (longest_streak_days >= current_streak_days)
);

COMMENT ON TABLE user_stats IS 'DERIVED CACHE of submission activity. Rebuildable from submissions; see scripts/verify.sql.';

-- ---------------------------------------------------------------------------
-- Onboarding survey (types/learning-preference.ts). Drives lib/roadmap/recommendation.ts.
-- One row per user — the survey is taken once and edited in Settings.
-- ---------------------------------------------------------------------------
CREATE TABLE learning_preferences (
  user_id                  uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  learning_goal            text,
  career_goal              text,
  current_level            current_level,
  content_priority         content_priority,
  weekly_study_hours       integer CHECK (weekly_study_hours IS NULL OR weekly_study_hours BETWEEN 0 AND 168),

  -- Native enum arrays, not JSON: typed, constrained, and GIN-indexable for the
  -- "roadmaps matching my interested fields" query.
  interested_fields        roadmap_field[]  NOT NULL DEFAULT '{}',
  preferred_learning_styles learning_style[] NOT NULL DEFAULT '{}',

  reminders_enabled        boolean NOT NULL DEFAULT true,
  reminder_time            time,
  adaptive_recommendations boolean NOT NULL DEFAULT true,
  completed_at             timestamptz,       -- null = survey skipped, drives the "khảo sát" CTA
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT learning_preferences_reminder_needs_time
    CHECK (NOT reminders_enabled OR reminder_time IS NOT NULL)
);

CREATE TRIGGER trg_learning_preferences_touch BEFORE UPDATE ON learning_preferences
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE INDEX idx_learning_preferences_fields
  ON learning_preferences USING gin (interested_fields);

-- ---------------------------------------------------------------------------
-- WeeklyStudySchedule: a real table, not a JSON blob, because the reminder scheduler
-- must query "which users have a session starting at 19:00 on Monday" across all users.
-- ---------------------------------------------------------------------------
CREATE TABLE study_schedule_slots (
  user_id          uuid    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  weekday          weekday NOT NULL,
  enabled          boolean NOT NULL DEFAULT false,
  start_time       time    NOT NULL,
  duration_minutes integer NOT NULL CHECK (duration_minutes BETWEEN 5 AND 1440),

  PRIMARY KEY (user_id, weekday)
);

CREATE INDEX idx_study_schedule_due ON study_schedule_slots (weekday, start_time)
  WHERE enabled;

COMMIT;
