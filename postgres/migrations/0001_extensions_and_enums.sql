-- 0001 — extensions, shared enums, shared helpers.
-- Every vocabulary the frontend expresses as a union type becomes a real enum here, so an
-- invalid value is rejected by the database rather than discovered in a UI switch statement.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive email / slug / invite code
CREATE EXTENSION IF NOT EXISTS btree_gin;  -- composite GIN for enum-array filters

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------
CREATE TYPE platform_role  AS ENUM ('learner', 'mentor', 'admin');
CREATE TYPE account_status AS ENUM ('active', 'suspended', 'deleted');

-- ---------------------------------------------------------------------------
-- Personalisation (types/learning-preference.ts)
-- ---------------------------------------------------------------------------
CREATE TYPE current_level    AS ENUM ('none', 'basic', 'intermediate', 'experienced');
CREATE TYPE roadmap_field    AS ENUM ('frontend', 'backend', 'fullstack', 'mobile', 'data_ai', 'foundation');
CREATE TYPE content_priority AS ENUM ('theory', 'practice', 'project');
CREATE TYPE learning_style   AS ENUM ('video', 'reading', 'practice', 'project', 'mentoring');
CREATE TYPE weekday          AS ENUM ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun');

-- ---------------------------------------------------------------------------
-- Content lifecycle + progression
-- ---------------------------------------------------------------------------
CREATE TYPE content_status   AS ENUM ('draft', 'published', 'archived');

-- How strictly prerequisite edges are enforced for a learner. `free` makes the whole
-- structure advisory without deleting any edge — this is what lets one dataset serve both
-- constrained and unconstrained learning. See docs/02-dependency-model.md §2.3.
CREATE TYPE progression_mode AS ENUM ('linear', 'graph', 'free');

CREATE TYPE lesson_type AS ENUM ('video', 'article', 'exercise', 'quiz', 'challenge', 'project');

-- ---------------------------------------------------------------------------
-- Exercises
-- ---------------------------------------------------------------------------
-- Single difficulty vocabulary. The frontend currently carries three ("Cơ bản"/"Trung bình"/
-- "Nâng cao", easy/medium/hard, and PracticeItem.level); Vietnamese labels are presentation.
CREATE TYPE exercise_difficulty AS ENUM ('easy', 'medium', 'hard');
CREATE TYPE exercise_kind       AS ENUM ('code', 'theory', 'quiz');
CREATE TYPE exercise_source     AS ENUM ('ai', 'manual');
CREATE TYPE exercise_set_kind   AS ENUM ('collection', 'track', 'daily');

-- Full authoring/moderation lifecycle, from types/study-group-detail.ts ExerciseStatus.
CREATE TYPE exercise_status AS ENUM (
  'draft', 'pending_review', 'changes_requested', 'rejected',
  'published', 'closed', 'hidden', 'archived'
);

-- ---------------------------------------------------------------------------
-- Progression state
-- ---------------------------------------------------------------------------
CREATE TYPE enrollment_status       AS ENUM ('active', 'completed', 'paused', 'dropped');
CREATE TYPE progress_status         AS ENUM ('not_started', 'in_progress', 'completed');
CREATE TYPE exercise_progress_status AS ENUM ('todo', 'attempted', 'solved');

-- ---------------------------------------------------------------------------
-- Collaboration
-- ---------------------------------------------------------------------------
CREATE TYPE group_role       AS ENUM ('owner', 'deputy', 'member');
CREATE TYPE group_status     AS ENUM ('active', 'archived');
CREATE TYPE member_status    AS ENUM ('invited', 'active', 'removed');
CREATE TYPE document_status  AS ENUM ('published', 'pending', 'changes', 'rejected', 'hidden');
CREATE TYPE ai_verdict       AS ENUM ('valid', 'warning', 'invalid');
CREATE TYPE assignment_status AS ENUM ('notstarted', 'inprogress', 'done', 'late');
CREATE TYPE review_status    AS ENUM ('pending', 'approved', 'needsfix');

CREATE TYPE group_permission AS ENUM (
  'upload_doc', 'create_exercise', 'edit_exercise',
  'delete_doc', 'review_submission', 'remove_member'
);

CREATE TYPE submission_verdict AS ENUM (
  'accepted', 'wrong_answer', 'compile_error',
  'runtime_error', 'timeout', 'memory_exceeded', 'pending'
);

-- ---------------------------------------------------------------------------
-- Shared helper: keep updated_at honest without relying on the application.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

COMMIT;
