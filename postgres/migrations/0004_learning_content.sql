-- 0004 — the learning hierarchy: roadmap → course → chapter → lesson.
--
-- Two things the frontend conflates are split here:
--   1. `position` (display order) vs prerequisite edges (gating)  — edges live in 0006.
--   2. content vs per-user state — isCompleted/isLocked/progressPercent/status move to 0007.

BEGIN;

-- ---------------------------------------------------------------------------
-- Roadmaps
-- ---------------------------------------------------------------------------
CREATE TABLE roadmaps (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug              citext NOT NULL UNIQUE,
  title             text   NOT NULL,
  short_description text,
  description       text,
  field             roadmap_field NOT NULL,
  level             current_level NOT NULL,
  cover_image_url   text,

  -- Authored estimate. Kept as an override rather than always summing course hours, because
  -- a roadmap may be published before every course exists (the frontend already does this).
  estimated_hours   integer CHECK (estimated_hours IS NULL OR estimated_hours > 0),

  -- Default enforcement for this roadmap's course edges; a learner may override per enrolment.
  progression_mode  progression_mode NOT NULL DEFAULT 'graph',

  -- The human sentence from Roadmap.prerequisites[]. Display only — real gating is in 0006.
  -- Kept because some prerequisites genuinely aren't links ("Biết dùng máy tính cơ bản").
  prerequisite_note text,

  status            content_status NOT NULL DEFAULT 'draft',
  popularity_score  integer NOT NULL DEFAULT 0 CHECK (popularity_score BETWEEN 0 AND 100),
  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  published_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT roadmaps_published_needs_date
    CHECK (status <> 'published' OR published_at IS NOT NULL)
);

CREATE TRIGGER trg_roadmaps_touch BEFORE UPDATE ON roadmaps
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Ordered prose lists (learningOutcomes[], targetAudience[]).
CREATE TABLE roadmap_outcomes (
  roadmap_id uuid NOT NULL REFERENCES roadmaps(id) ON DELETE CASCADE,
  position   integer NOT NULL CHECK (position > 0),
  text       text    NOT NULL,
  PRIMARY KEY (roadmap_id, position)
);

CREATE TABLE roadmap_audiences (
  roadmap_id uuid NOT NULL REFERENCES roadmaps(id) ON DELETE CASCADE,
  position   integer NOT NULL CHECK (position > 0),
  text       text    NOT NULL,
  PRIMARY KEY (roadmap_id, position)
);

CREATE TABLE roadmap_technologies (
  roadmap_id    uuid NOT NULL REFERENCES roadmaps(id)     ON DELETE CASCADE,
  technology_id uuid NOT NULL REFERENCES technologies(id) ON DELETE RESTRICT,
  PRIMARY KEY (roadmap_id, technology_id)
);

-- ---------------------------------------------------------------------------
-- Courses
-- ---------------------------------------------------------------------------
CREATE TABLE courses (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug              citext NOT NULL UNIQUE,
  title             text   NOT NULL,
  description       text,
  cover_image_url   text,
  level             current_level NOT NULL,
  duration_hours    integer CHECK (duration_hours IS NULL OR duration_hours > 0),

  -- Course.instructor was a free string mixing name and job title; now a real account.
  instructor_id     uuid REFERENCES users(id) ON DELETE SET NULL,

  prerequisite_note text,
  -- Governs BOTH chapter and lesson gating inside this course. One policy per course.
  progression_mode  progression_mode NOT NULL DEFAULT 'graph',
  status            content_status NOT NULL DEFAULT 'draft',

  -- CACHE. Authoritative counts the frontend already keeps separately so a course can report
  -- realistic totals before its curriculum is written. Reconciled in scripts/verify.sql.
  total_chapters    integer NOT NULL DEFAULT 0 CHECK (total_chapters >= 0),
  total_lessons     integer NOT NULL DEFAULT 0 CHECK (total_lessons  >= 0),
  rating_avg        numeric(3,2) CHECK (rating_avg IS NULL OR rating_avg BETWEEN 1 AND 5),
  rating_count      integer NOT NULL DEFAULT 0 CHECK (rating_count     >= 0),
  enrollment_count  integer NOT NULL DEFAULT 0 CHECK (enrollment_count >= 0),

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  published_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT courses_published_needs_date
    CHECK (status <> 'published' OR published_at IS NOT NULL)
);

CREATE TRIGGER trg_courses_touch BEFORE UPDATE ON courses
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE course_outcomes (
  course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  position  integer NOT NULL CHECK (position > 0),
  text      text    NOT NULL,
  PRIMARY KEY (course_id, position)
);

CREATE TABLE course_technologies (
  course_id     uuid NOT NULL REFERENCES courses(id)      ON DELETE CASCADE,
  technology_id uuid NOT NULL REFERENCES technologies(id) ON DELETE RESTRICT,
  PRIMARY KEY (course_id, technology_id)
);

-- Ratings need a source of truth; rating_avg/rating_count alone are unauditable.
CREATE TABLE course_reviews (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id  uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  rating     smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment    text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (course_id, user_id)          -- one review per learner per course
);

CREATE TRIGGER trg_course_reviews_touch BEFORE UPDATE ON course_reviews
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Roadmap ↔ Course membership.
-- A first-class entity, not a plain join: position and gating belong to "this course inside
-- this roadmap". The same course can be #2 with prerequisites in one roadmap and #5 with
-- none in another. Prerequisite edges in 0006 therefore point at roadmap_courses.id.
-- ---------------------------------------------------------------------------
CREATE TABLE roadmap_courses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  roadmap_id  uuid NOT NULL REFERENCES roadmaps(id) ON DELETE CASCADE,
  -- RESTRICT: deleting a course still referenced by a roadmap must fail loudly rather than
  -- silently reshaping somebody's curriculum. Retire content with status='archived'.
  course_id   uuid NOT NULL REFERENCES courses(id)  ON DELETE RESTRICT,
  position    integer NOT NULL CHECK (position > 0),
  is_optional boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (roadmap_id, course_id),
  -- DEFERRABLE so a drag-reorder can swap two positions inside one transaction.
  CONSTRAINT roadmap_courses_position_unique UNIQUE (roadmap_id, position) DEFERRABLE INITIALLY IMMEDIATE,
  -- Composite-unique target so roadmap_course_prerequisites (0006) can enforce
  -- "both endpoints in the same roadmap" with a plain FK instead of a trigger.
  CONSTRAINT roadmap_courses_id_roadmap_unique UNIQUE (roadmap_id, id)
);

-- ---------------------------------------------------------------------------
-- Chapters
-- ---------------------------------------------------------------------------
CREATE TABLE chapters (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id   uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title       text NOT NULL,
  description text,
  position    integer NOT NULL CHECK (position > 0),   -- DISPLAY ORDER ONLY
  is_optional boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chapters_position_unique UNIQUE (course_id, position) DEFERRABLE INITIALLY IMMEDIATE,
  -- Lets chapter_prerequisites (0006) and lessons.course_id enforce scope via plain FKs.
  CONSTRAINT chapters_id_course_unique UNIQUE (course_id, id)
);

CREATE TRIGGER trg_chapters_touch BEFORE UPDATE ON chapters
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Lessons
-- ---------------------------------------------------------------------------
CREATE TABLE lessons (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_id       uuid NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,

  -- Denormalised owning course. NOT a redundancy risk: the composite FK below makes it
  -- provably equal to the chapter's course_id, and it lets lesson_prerequisites (0006)
  -- reject cross-course edges with a plain FK rather than a trigger.
  course_id        uuid NOT NULL,

  title            text NOT NULL,
  type             lesson_type NOT NULL,
  duration_minutes integer CHECK (duration_minutes IS NULL OR duration_minutes > 0),

  -- Genuine content attribute (free preview), unlike isLocked/isCompleted which were per-user.
  is_preview       boolean NOT NULL DEFAULT false,
  is_optional      boolean NOT NULL DEFAULT false,
  position         integer NOT NULL CHECK (position > 0),   -- DISPLAY ORDER ONLY

  -- type='exercise' lessons had no link to the exercise they run. FK added in 0005.
  exercise_id      uuid,

  -- MongoDB lesson_contents._id. Nullable while the body is being authored.
  content_ref      text,

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT lessons_position_unique UNIQUE (chapter_id, position) DEFERRABLE INITIALLY IMMEDIATE,
  -- Only exercise-ish lessons may bind an exercise.
  CONSTRAINT lessons_exercise_only_for_exercise_types
    CHECK (exercise_id IS NULL OR type IN ('exercise', 'quiz', 'challenge', 'project')),

  -- Proves course_id === chapters.course_id. Without this the denormalised column could drift.
  CONSTRAINT lessons_chapter_in_course_fkey
    FOREIGN KEY (course_id, chapter_id) REFERENCES chapters (course_id, id) ON DELETE CASCADE,
  -- Composite-unique target for lesson_prerequisites' same-course enforcement.
  CONSTRAINT lessons_id_course_unique UNIQUE (course_id, id)
);

CREATE TRIGGER trg_lessons_touch BEFORE UPDATE ON lessons
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

COMMENT ON COLUMN lessons.position IS 'Display order within the chapter. Carries NO progression meaning — gating lives in lesson_prerequisites.';

COMMIT;
