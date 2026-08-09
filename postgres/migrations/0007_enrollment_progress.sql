-- 0007 — enrolment and per-user progress.
--
-- Everything here was previously a column on a SHARED CONTENT record in the frontend
-- (Lesson.isCompleted, Course.status/progressPercent, Roadmap.userProgress,
-- PracticeItem.status/isFavorite). With real users that is a correctness bug: two learners
-- would overwrite each other. See docs/00-frontend-review.md §3.1.
--
-- Persist vs derive vs cache (docs/01-domain-model.md §3.1):
--   lesson_progress / exercise_progress  PERSISTED  — irreducible learner facts
--   chapter progress                     DERIVED    — counted at read time, never stored
--   course / roadmap progress            CACHED     — on the enrolment row, trigger-maintained

BEGIN;

-- ---------------------------------------------------------------------------
-- Roadmap enrolment
-- ---------------------------------------------------------------------------
CREATE TABLE roadmap_enrollments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  roadmap_id       uuid NOT NULL REFERENCES roadmaps(id) ON DELETE CASCADE,
  status           enrollment_status NOT NULL DEFAULT 'active',

  -- Learner opt-in/out of prerequisite enforcement. NULL inherits roadmaps.progression_mode.
  mode_override    progression_mode,

  -- CACHE — see fn_refresh_roadmap_progress in 0012.
  completed_courses integer NOT NULL DEFAULT 0 CHECK (completed_courses >= 0),
  progress_percent  numeric(5,2) NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),

  started_at       timestamptz NOT NULL DEFAULT now(),
  completed_at     timestamptz,
  last_activity_at timestamptz,

  UNIQUE (user_id, roadmap_id),
  CONSTRAINT roadmap_enrollments_completed_consistency
    CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

-- ---------------------------------------------------------------------------
-- Course enrolment. `via_roadmap_id` records how the learner arrived, so a course taken
-- standalone and the same course inside a roadmap are one enrolment, not two.
-- ---------------------------------------------------------------------------
CREATE TABLE course_enrollments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  course_id        uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  via_roadmap_id   uuid REFERENCES roadmaps(id) ON DELETE SET NULL,
  status           enrollment_status NOT NULL DEFAULT 'active',

  -- Learner opt-in/out of chapter+lesson gating. NULL inherits courses.progression_mode.
  mode_override    progression_mode,

  -- CACHE — see fn_refresh_course_progress in 0012.
  completed_lessons integer NOT NULL DEFAULT 0 CHECK (completed_lessons >= 0),
  progress_percent  numeric(5,2) NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),

  started_at       timestamptz NOT NULL DEFAULT now(),
  completed_at     timestamptz,
  last_activity_at timestamptz,

  UNIQUE (user_id, course_id),
  CONSTRAINT course_enrollments_completed_consistency
    CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

-- ---------------------------------------------------------------------------
-- Lesson progress — SOURCE OF TRUTH for all course/roadmap percentages.
-- Natural PK (user, lesson): a learner has exactly one progress record per lesson.
-- ---------------------------------------------------------------------------
CREATE TABLE lesson_progress (
  user_id               uuid NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  lesson_id             uuid NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  status                progress_status NOT NULL DEFAULT 'not_started',
  time_spent_seconds    integer NOT NULL DEFAULT 0 CHECK (time_spent_seconds >= 0),
  -- Video resume point; meaningless for article lessons, hence nullable.
  last_position_seconds integer CHECK (last_position_seconds IS NULL OR last_position_seconds >= 0),
  started_at            timestamptz,
  completed_at          timestamptz,
  updated_at            timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, lesson_id),
  CONSTRAINT lesson_progress_completed_consistency
    CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

CREATE TRIGGER trg_lesson_progress_touch BEFORE UPDATE ON lesson_progress
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Exercise progress — SOURCE OF TRUTH for practice state.
-- Derivable from submissions, but kept because every catalogue row needs status/favourite
-- without scanning the submission history, and `is_favorite` has no submission at all.
-- ---------------------------------------------------------------------------
CREATE TABLE exercise_progress (
  user_id         uuid NOT NULL REFERENCES users(id)     ON DELETE CASCADE,
  exercise_id     uuid NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  status          exercise_progress_status NOT NULL DEFAULT 'todo',
  best_score      integer CHECK (best_score IS NULL OR best_score BETWEEN 0 AND 100),
  attempt_count   integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  is_favorite     boolean NOT NULL DEFAULT false,
  first_solved_at timestamptz,
  last_attempt_at timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, exercise_id),
  CONSTRAINT exercise_progress_solved_consistency
    CHECK ((status = 'solved') = (first_solved_at IS NOT NULL)),
  CONSTRAINT exercise_progress_attempted_has_attempts
    CHECK (status = 'todo' OR attempt_count > 0)
);

CREATE TRIGGER trg_exercise_progress_touch BEFORE UPDATE ON exercise_progress
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

COMMENT ON TABLE lesson_progress IS 'Source of truth. course_enrollments.progress_percent and roadmap_enrollments.progress_percent are caches derived from this table.';

COMMIT;
