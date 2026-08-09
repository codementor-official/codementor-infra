-- 0006 — prerequisite edges at five levels.
--
-- One mechanism everywhere (docs/02-dependency-model.md):
--   target_id    the thing being gated
--   source_id    what must be completed first
--   group_index  edges in the SAME group are ANDed; different groups are ORed (DNF)
--
-- `target` unlocks when at least one group is fully satisfied. No rows = always available.
--
-- Scope violations (cross-course, cross-roadmap, cross-set edges) are rejected by composite
-- FOREIGN KEYS rather than triggers — cheaper, and impossible to bypass. Cycles need real
-- graph traversal and are handled by triggers in 0010.

BEGIN;

-- ---------------------------------------------------------------------------
-- Roadmap → Course. Endpoints are roadmap_courses rows, so gating is per-roadmap:
-- the same course may be gated in one roadmap and free in another.
-- ---------------------------------------------------------------------------
CREATE TABLE roadmap_course_prerequisites (
  roadmap_id              uuid NOT NULL,
  target_roadmap_course_id uuid NOT NULL,
  source_roadmap_course_id uuid NOT NULL,
  group_index             smallint NOT NULL DEFAULT 0 CHECK (group_index >= 0),
  created_at              timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (target_roadmap_course_id, source_roadmap_course_id, group_index),
  CONSTRAINT rcp_no_self_reference CHECK (source_roadmap_course_id <> target_roadmap_course_id),

  -- Both endpoints must live in the SAME roadmap — enforced declaratively.
  CONSTRAINT rcp_target_in_roadmap FOREIGN KEY (roadmap_id, target_roadmap_course_id)
    REFERENCES roadmap_courses (roadmap_id, id) ON DELETE CASCADE,
  CONSTRAINT rcp_source_in_roadmap FOREIGN KEY (roadmap_id, source_roadmap_course_id)
    REFERENCES roadmap_courses (roadmap_id, id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- Course → Course, intrinsic and roadmap-independent.
-- "Spring Boot REST API needs Java Core, wherever you meet it."
-- Distinct from the roadmap edges above, which are one curriculum's chosen sequence.
-- ---------------------------------------------------------------------------
CREATE TABLE course_prerequisites (
  target_course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  source_course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  group_index      smallint NOT NULL DEFAULT 0 CHECK (group_index >= 0),
  created_at       timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (target_course_id, source_course_id, group_index),
  CONSTRAINT cp_no_self_reference CHECK (source_course_id <> target_course_id)
);

-- ---------------------------------------------------------------------------
-- Chapter → Chapter, scoped to one course.
-- ---------------------------------------------------------------------------
CREATE TABLE chapter_prerequisites (
  course_id         uuid NOT NULL,
  target_chapter_id uuid NOT NULL,
  source_chapter_id uuid NOT NULL,
  group_index       smallint NOT NULL DEFAULT 0 CHECK (group_index >= 0),
  created_at        timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (target_chapter_id, source_chapter_id, group_index),
  CONSTRAINT chp_no_self_reference CHECK (source_chapter_id <> target_chapter_id),

  CONSTRAINT chp_target_in_course FOREIGN KEY (course_id, target_chapter_id)
    REFERENCES chapters (course_id, id) ON DELETE CASCADE,
  CONSTRAINT chp_source_in_course FOREIGN KEY (course_id, source_chapter_id)
    REFERENCES chapters (course_id, id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- Lesson → Lesson, scoped to one course.
--
-- Cross-CHAPTER edges within a course are allowed (a chapter-2 lesson may legitimately
-- require a chapter-1 lesson); cross-COURSE edges are rejected by the composite FK.
--
-- This is the level the brief calls out: `position` alone cannot express
--   Lesson 1 ──┬──▶ Lesson 2
--              ├──▶ Lesson 3
--              └──▶ Lesson 4      (2/3/4 independent, any order, after 1)
-- ---------------------------------------------------------------------------
CREATE TABLE lesson_prerequisites (
  course_id        uuid NOT NULL,
  target_lesson_id uuid NOT NULL,
  source_lesson_id uuid NOT NULL,
  group_index      smallint NOT NULL DEFAULT 0 CHECK (group_index >= 0),
  created_at       timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (target_lesson_id, source_lesson_id, group_index),
  CONSTRAINT lp_no_self_reference CHECK (source_lesson_id <> target_lesson_id),

  CONSTRAINT lp_target_in_course FOREIGN KEY (course_id, target_lesson_id)
    REFERENCES lessons (course_id, id) ON DELETE CASCADE,
  CONSTRAINT lp_source_in_course FOREIGN KEY (course_id, source_lesson_id)
    REFERENCES lessons (course_id, id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- Exercise → Exercise, scoped to a SET.
--
-- Set-scoping is what supports constrained AND unconstrained practice over the same
-- exercises with no duplication: an exercise gated inside "Nhập môn thuật toán" is still
-- free-choice in the catalogue and inside "Top 100 phỏng vấn".
--
-- The composite FK targets exercise_set_items' primary key, so an edge can only reference
-- exercises that are actually members of that set.
-- ---------------------------------------------------------------------------
CREATE TABLE exercise_prerequisites (
  set_id             uuid NOT NULL,
  target_exercise_id uuid NOT NULL,
  source_exercise_id uuid NOT NULL,
  group_index        smallint NOT NULL DEFAULT 0 CHECK (group_index >= 0),
  created_at         timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (set_id, target_exercise_id, source_exercise_id, group_index),
  CONSTRAINT ep_no_self_reference CHECK (source_exercise_id <> target_exercise_id),

  CONSTRAINT ep_target_in_set FOREIGN KEY (set_id, target_exercise_id)
    REFERENCES exercise_set_items (set_id, exercise_id) ON DELETE CASCADE,
  CONSTRAINT ep_source_in_set FOREIGN KEY (set_id, source_exercise_id)
    REFERENCES exercise_set_items (set_id, exercise_id) ON DELETE CASCADE
);

COMMENT ON COLUMN lesson_prerequisites.group_index IS
  'Disjunctive normal form: same group = AND, different groups = OR. (A,0),(B,0) means A AND B; (A,0),(B,1) means A OR B.';

COMMIT;
