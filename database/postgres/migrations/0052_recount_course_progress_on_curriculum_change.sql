-- 0052 — keep course_enrollments.completed_lessons / progress_percent honest when the curriculum
-- changes, not only when lesson_progress changes.
--
-- 0012 recomputes a learner's cache from lesson_progress. Adding a lesson, deleting one (its
-- lesson_progress rows cascade away while the lesson is already gone, so the 0012 trigger skips
-- them) or toggling is_optional left every enrolment of that course with stale numbers — e.g.
-- "2/15 · 66.67%" with no lesson ticked. This recounts the counters only: status, completed_at and
-- last_activity_at are left alone so a curriculum edit never reopens a finished course, never
-- revokes a certificate and never counts as learner activity.

BEGIN;

CREATE FUNCTION fn_recount_course_progress(p_course uuid)
RETURNS integer
LANGUAGE sql AS $$
  WITH total AS (
    SELECT count(*) FILTER (WHERE NOT l.is_optional) AS n FROM lessons l WHERE l.course_id = p_course
  ), done AS (
    SELECT lp.user_id, count(*) AS n
    FROM lesson_progress lp JOIN lessons l ON l.id = lp.lesson_id
    WHERE l.course_id = p_course AND lp.status = 'completed' AND NOT l.is_optional
    GROUP BY lp.user_id
  ), fresh AS (
    SELECT ce.user_id, COALESCE(d.n, 0)::int AS done,
           CASE WHEN t.n = 0 THEN 0 ELSE round(COALESCE(d.n, 0)::numeric * 100 / t.n, 2) END AS pct
    FROM course_enrollments ce CROSS JOIN total t LEFT JOIN done d ON d.user_id = ce.user_id
    WHERE ce.course_id = p_course
  ), changed AS (
    UPDATE course_enrollments ce
       SET completed_lessons = f.done, progress_percent = f.pct
      FROM fresh f
     WHERE ce.course_id = p_course AND ce.user_id = f.user_id
       AND (ce.completed_lessons, ce.progress_percent) IS DISTINCT FROM (f.done, f.pct)
    RETURNING 1
  )
  SELECT count(*)::int FROM changed;
$$;

CREATE FUNCTION fn_on_lesson_curriculum_progress() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP <> 'DELETE' THEN
    PERFORM fn_recount_course_progress(NEW.course_id);
  END IF;
  IF TG_OP = 'DELETE' OR OLD.course_id IS DISTINCT FROM NEW.course_id THEN
    PERFORM fn_recount_course_progress(OLD.course_id);
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_lessons_progress_recount
  AFTER INSERT OR DELETE OR UPDATE OF is_optional, course_id ON lessons
  FOR EACH ROW EXECUTE FUNCTION fn_on_lesson_curriculum_progress();

-- One-off backfill for enrolments that drifted before this trigger existed.
DO $$
DECLARE v_changed integer;
BEGIN
  SELECT COALESCE(sum(fn_recount_course_progress(c.id)), 0) INTO v_changed FROM courses c;
  RAISE NOTICE '0052: recounted % course enrolment(s)', v_changed;
END $$;

COMMIT;
