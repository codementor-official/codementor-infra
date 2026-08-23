-- 0021 — drop the unused branches of the prerequisite graph.
--
-- 0006 built five AND-OR prerequisite tables (roadmap_course / course / chapter / lesson /
-- exercise) plus 0011's fn_*_available functions to evaluate them. Only the lesson level ever
-- got wired to the application: `saveCurriculum` (learning-service) derives lesson_prerequisites
-- automatically from curriculum order — always a single AND group, never OR — and
-- fn_lesson_available is the only one of the six functions any service calls.
--
-- The other four tables have no writer anywhere in the app (only this repo's own seed/verify
-- ever inserted into them) and their four availability functions have no caller. With the tables
-- gone, `progression_mode = 'graph'` at the roadmap/course/chapter/exercise-set level would
-- silently fall through fn_*_available's "no prerequisites = open" branch anyway — nothing before
-- this migration relied on those rows existing outside this repo's own tests.
--
-- lesson_prerequisites, fn_lesson_available, and the generic fn_prevent_dependency_cycle are
-- untouched — that path is live.

BEGIN;

DROP TABLE roadmap_course_prerequisites;
DROP TABLE course_prerequisites;
DROP TABLE chapter_prerequisites;
DROP TABLE exercise_prerequisites;

DROP FUNCTION fn_roadmap_course_available(uuid, uuid);
DROP FUNCTION fn_course_available(uuid, uuid);
DROP FUNCTION fn_course_completed(uuid, uuid);
DROP FUNCTION fn_chapter_available(uuid, uuid);
DROP FUNCTION fn_chapter_completed(uuid, uuid);
DROP FUNCTION fn_exercise_available(uuid, uuid, uuid);

-- Only referenced by triggers on the tables just dropped (trg_cp_no_archived,
-- trg_rcp_no_archived, trg_ep_no_archived) — those triggers went with their tables.
DROP FUNCTION fn_reject_archived_course_edge();
DROP FUNCTION fn_reject_archived_roadmap_course_edge();
DROP FUNCTION fn_reject_archived_exercise_edge();

COMMIT;
