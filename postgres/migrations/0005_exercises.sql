-- 0005 — exercises and curated exercise sets.
--
-- The frontend carries FOUR incompatible shapes for one concept (PracticeItem, Problem,
-- AuthoredCodeProblem, GroupExercise — see docs/00-frontend-review.md §2.4). They are the same
-- object at different lifecycle stages, unified here into:
--
--   exercises            relational spine  (identity, lifecycle, FK target)
--   mongo exercise_contents  document body (statement, test cases, hints, language config)
--
-- Why a spine at all, when the brief puts exercises in MongoDB: dependencies, progress,
-- assignments and set membership all need enforceable foreign keys and cycle checks, which a
-- cross-database string reference cannot provide. See docs/04-design-decisions.md §1.

BEGIN;

CREATE TABLE exercises (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug             citext NOT NULL UNIQUE,      -- replaces PracticeItem.href / solveSlug
  title            text NOT NULL,
  summary          text,
  kind             exercise_kind       NOT NULL DEFAULT 'code',
  difficulty       exercise_difficulty NOT NULL,
  status           exercise_status     NOT NULL DEFAULT 'draft',
  source           exercise_source     NOT NULL DEFAULT 'manual',

  xp_reward        integer NOT NULL DEFAULT 0 CHECK (xp_reward >= 0),
  estimated_minutes integer CHECK (estimated_minutes IS NULL OR estimated_minutes > 0),

  -- Typed judge limits. The frontend stored these as display strings ("1 giây", "256MB").
  time_limit_ms    integer NOT NULL DEFAULT 1000   CHECK (time_limit_ms BETWEEN 100 AND 60000),
  memory_limit_kb  integer NOT NULL DEFAULT 262144 CHECK (memory_limit_kb BETWEEN 1024 AND 4194304),

  author_id        uuid REFERENCES users(id) ON DELETE SET NULL,
  -- Group-private exercises (GroupExercise). NULL = public catalogue. FK added in 0008.
  owner_group_id   uuid,

  -- MongoDB exercise_contents._id. Nullable while the body is being authored.
  content_ref      text,

  -- CACHE, derived from submissions / exercise_progress.
  acceptance_rate  numeric(5,2) CHECK (acceptance_rate IS NULL OR acceptance_rate BETWEEN 0 AND 100),
  solver_count     integer NOT NULL DEFAULT 0 CHECK (solver_count  >= 0),
  attempt_count    integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),

  published_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT exercises_published_needs_content
    CHECK (status <> 'published' OR content_ref IS NOT NULL),
  CONSTRAINT exercises_solver_le_attempt CHECK (solver_count <= attempt_count)
);

CREATE TRIGGER trg_exercises_touch BEFORE UPDATE ON exercises
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Now that exercises exist, bind the lesson → exercise link from 0004.
ALTER TABLE lessons
  ADD CONSTRAINT lessons_exercise_id_fkey
  FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE SET NULL;

-- Vocabularies
CREATE TABLE exercise_tags (
  exercise_id uuid NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  tag_id      uuid NOT NULL REFERENCES tags(id)      ON DELETE RESTRICT,
  PRIMARY KEY (exercise_id, tag_id)
);

CREATE TABLE exercise_technologies (
  exercise_id   uuid NOT NULL REFERENCES exercises(id)    ON DELETE CASCADE,
  technology_id uuid NOT NULL REFERENCES technologies(id) ON DELETE RESTRICT,
  PRIMARY KEY (exercise_id, technology_id)
);

CREATE TABLE exercise_companies (
  exercise_id uuid NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  PRIMARY KEY (exercise_id, company_id)
);

-- ---------------------------------------------------------------------------
-- Exercise sets — curated collections ("Top 100 phỏng vấn", "Nhập môn thuật toán").
--
-- Dependencies are scoped to a SET rather than global, which is what lets the same exercise be
-- free-choice in the catalogue and gated inside a track WITHOUT duplicating it (brief §7).
-- ---------------------------------------------------------------------------
CREATE TABLE exercise_sets (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug             citext NOT NULL UNIQUE,
  title            text NOT NULL,
  description      text,
  kind             exercise_set_kind NOT NULL DEFAULT 'collection',
  -- Default enforcement; a learner may override per enrolment below.
  progression_mode progression_mode  NOT NULL DEFAULT 'free',
  status           content_status    NOT NULL DEFAULT 'draft',
  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_exercise_sets_touch BEFORE UPDATE ON exercise_sets
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE exercise_set_items (
  set_id      uuid NOT NULL REFERENCES exercise_sets(id) ON DELETE CASCADE,
  exercise_id uuid NOT NULL REFERENCES exercises(id)     ON DELETE CASCADE,
  position    integer NOT NULL CHECK (position > 0),      -- DISPLAY ORDER ONLY
  PRIMARY KEY (set_id, exercise_id),
  CONSTRAINT exercise_set_items_position_unique UNIQUE (set_id, position) DEFERRABLE INITIALLY IMMEDIATE
);

-- The learner-facing "constrained vs unconstrained" toggle the brief asks for (§7).
CREATE TABLE exercise_set_enrollments (
  user_id                  uuid NOT NULL REFERENCES users(id)         ON DELETE CASCADE,
  set_id                   uuid NOT NULL REFERENCES exercise_sets(id) ON DELETE CASCADE,
  -- NULL = inherit exercise_sets.progression_mode.
  progression_mode_override progression_mode,
  started_at               timestamptz NOT NULL DEFAULT now(),
  completed_at             timestamptz,
  PRIMARY KEY (user_id, set_id)
);

COMMENT ON COLUMN exercise_set_enrollments.progression_mode_override IS
  'Learner opt-in/out of prerequisite enforcement for this set. NULL inherits the set default. No content is duplicated to support either mode.';

COMMIT;
