-- 0018 — what the authoring and moderation flow needs and the schema did not have.
--
-- Additive only. No table is renamed, no column is dropped, no row is touched. Every
-- change here backs a rule that was already written down but had nothing enforcing it.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Courses and roadmaps had no way to be "waiting for review"
--
-- `content_status` was draft | published | archived, so an author could only jump
-- straight from a private draft to public. Exercises already had the full lifecycle in
-- `exercise_status`; these two did not, and the review queue has nothing to select on
-- without it.
--
-- Enum order is stored as a float per label, so inserting between existing labels is a
-- catalog edit — no table rewrite, no lock beyond the type itself.
-- ---------------------------------------------------------------------------
ALTER TYPE content_status ADD VALUE IF NOT EXISTS 'pending_review'    AFTER 'draft';
ALTER TYPE content_status ADD VALUE IF NOT EXISTS 'changes_requested' AFTER 'pending_review';
ALTER TYPE content_status ADD VALUE IF NOT EXISTS 'rejected'          AFTER 'changes_requested';

-- ---------------------------------------------------------------------------
-- 2. Rejecting without saying why
--
-- `rejected` and `changes_requested` existed for exercises with nowhere to put the
-- reason, so an author saw the verdict and not the cause.
-- ---------------------------------------------------------------------------
ALTER TABLE exercises ADD COLUMN rejection_reason text;
ALTER TABLE courses   ADD COLUMN rejection_reason text;
ALTER TABLE roadmaps  ADD COLUMN rejection_reason text;

COMMENT ON COLUMN exercises.rejection_reason IS
  'Lý do admin từ chối hoặc yêu cầu sửa. Xoá khi tác giả gửi duyệt lại.';

-- ---------------------------------------------------------------------------
-- 3. Fork provenance
--
-- ON DELETE SET NULL, not CASCADE: a fork is an independent copy from the moment it is
-- created. Deleting the original must leave the fork alone, only losing the note about
-- where it came from. This column carries no synchronisation semantics whatsoever.
-- ---------------------------------------------------------------------------
ALTER TABLE exercises
  ADD COLUMN forked_from_id uuid REFERENCES exercises(id) ON DELETE SET NULL;

COMMENT ON COLUMN exercises.forked_from_id IS
  'Chỉ ghi nhận nguồn gốc để hiển thị. KHÔNG có logic đồng bộ nào giữa bản gốc và bản fork.';

-- Partial: the overwhelming majority of exercises are not forks.
CREATE INDEX idx_exercises_forked_from
  ON exercises (forked_from_id) WHERE forked_from_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. Deleting an exercise silently emptied the lesson that ran it
--
-- The FK was ON DELETE SET NULL. A lesson of type='exercise' whose exercise_id became
-- NULL still passes `lessons_exercise_only_for_exercise_types`, still counts toward
-- `total_lessons`, and still appears in the curriculum — as a slot that opens onto
-- nothing. The learner sees a blank lesson; nothing anywhere reports an error.
--
-- RESTRICT makes the database refuse instead, which is what the content model asks for:
-- retire content with status='archived', do not delete rows out from under a curriculum.
-- ---------------------------------------------------------------------------
ALTER TABLE lessons DROP CONSTRAINT lessons_exercise_id_fkey;
ALTER TABLE lessons
  ADD CONSTRAINT lessons_exercise_id_fkey
  FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE RESTRICT;

-- ---------------------------------------------------------------------------
-- 5. The same exercise could be added to one chapter twice
--
-- Two lessons in a chapter pointing at one exercise means the learner solves it once and
-- sees one of the two slots stay unfinished forever, because progress is keyed by
-- (user, exercise) and not by lesson.
--
-- Partial index rather than a table constraint: exercise_id is NULL for every article
-- and video lesson, and a plain UNIQUE would be satisfied by NULLs anyway but would
-- carry every one of those rows for nothing.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX lessons_exercise_unique_per_chapter
  ON lessons (chapter_id, exercise_id) WHERE exercise_id IS NOT NULL;

COMMIT;
