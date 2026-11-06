-- 0047 — roadmap order becomes a soft lock (backend ADR 0005, phase 1).
--
-- Learners may start a roadmap course before finishing the required ones in front of it, after
-- confirming a warning. The backend still allows it; this column only records that it happened,
-- so lecturers and admins can see how often learners skip the order. Set once at enrolment and
-- never cleared: finishing the earlier course later does not undo the fact that they skipped.
BEGIN;

ALTER TABLE course_enrollments
  ADD COLUMN IF NOT EXISTS started_out_of_order boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN course_enrollments.started_out_of_order IS
  'True when the learner enrolled from a roadmap while an earlier required course was not completed.';

COMMIT;
