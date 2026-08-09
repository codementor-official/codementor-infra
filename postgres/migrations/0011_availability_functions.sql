-- 0011 — availability resolution.
--
-- The single place that answers "can this learner open this thing yet?". The API layer calls
-- these instead of re-implementing the rule, so gating can never drift between screens.
--
-- Mode semantics (docs/02-dependency-model.md §2.3):
--   free    everything open; edges are advisory only
--   linear  ordering IS the gate — every earlier non-optional sibling must be completed.
--           No edges need to be authored at all.
--   graph   the DNF prerequisite edges are evaluated: same group = AND, across groups = OR
--
-- Effective mode = learner's enrolment override, else the container's default.

BEGIN;

-- ---------------------------------------------------------------------------
-- Lessons
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_lesson_available(p_user uuid, p_lesson uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_course  uuid;
  v_mode    progression_mode;
  v_ch_pos  integer;
  v_l_pos   integer;
  v_ok      boolean;
BEGIN
  SELECT l.course_id, ch.position, l.position
    INTO v_course, v_ch_pos, v_l_pos
  FROM lessons l
  JOIN chapters ch ON ch.id = l.chapter_id
  WHERE l.id = p_lesson;

  IF v_course IS NULL THEN
    RETURN false;                       -- unknown lesson
  END IF;

  SELECT COALESCE(ce.mode_override, c.progression_mode)
    INTO v_mode
  FROM courses c
  LEFT JOIN course_enrollments ce
         ON ce.course_id = c.id AND ce.user_id = p_user
  WHERE c.id = v_course;

  IF v_mode = 'free' THEN
    RETURN true;
  END IF;

  IF v_mode = 'linear' THEN
    -- Every earlier non-optional lesson in the course must be completed.
    SELECT NOT EXISTS (
      SELECT 1
      FROM lessons l
      JOIN chapters ch ON ch.id = l.chapter_id
      WHERE l.course_id = v_course
        AND NOT l.is_optional
        AND (ch.position, l.position) < (v_ch_pos, v_l_pos)
        AND NOT EXISTS (
          SELECT 1 FROM lesson_progress lp
          WHERE lp.user_id = p_user AND lp.lesson_id = l.id AND lp.status = 'completed'
        )
    ) INTO v_ok;
    RETURN v_ok;
  END IF;

  -- graph: no prerequisites at all, or at least one group fully satisfied.
  SELECT NOT EXISTS (SELECT 1 FROM lesson_prerequisites WHERE target_lesson_id = p_lesson)
      OR EXISTS (
           SELECT 1
           FROM lesson_prerequisites lp
           WHERE lp.target_lesson_id = p_lesson
           GROUP BY lp.group_index
           HAVING bool_and(EXISTS (
             SELECT 1 FROM lesson_progress p
             WHERE p.user_id = p_user
               AND p.lesson_id = lp.source_lesson_id
               AND p.status = 'completed'
           ))
         )
    INTO v_ok;

  RETURN v_ok;
END;
$$;

COMMENT ON FUNCTION fn_lesson_available IS 'Replaces the frontend Lesson.isLocked flag, which was hardcoded on 4 seed rows and could not vary per learner.';

-- ---------------------------------------------------------------------------
-- Chapters — a chapter is open when its prerequisites are met; completion of a chapter
-- means all of its non-optional lessons are done.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_chapter_completed(p_user uuid, p_chapter uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM lessons l
    WHERE l.chapter_id = p_chapter
      AND NOT l.is_optional
      AND NOT EXISTS (
        SELECT 1 FROM lesson_progress lp
        WHERE lp.user_id = p_user AND lp.lesson_id = l.id AND lp.status = 'completed'
      )
  )
  -- an empty chapter is not "completed"
  AND EXISTS (SELECT 1 FROM lessons l2 WHERE l2.chapter_id = p_chapter AND NOT l2.is_optional);
$$;

CREATE FUNCTION fn_chapter_available(p_user uuid, p_chapter uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_course uuid;
  v_mode   progression_mode;
  v_pos    integer;
  v_ok     boolean;
BEGIN
  SELECT ch.course_id, ch.position INTO v_course, v_pos
  FROM chapters ch WHERE ch.id = p_chapter;

  IF v_course IS NULL THEN RETURN false; END IF;

  SELECT COALESCE(ce.mode_override, c.progression_mode) INTO v_mode
  FROM courses c
  LEFT JOIN course_enrollments ce ON ce.course_id = c.id AND ce.user_id = p_user
  WHERE c.id = v_course;

  IF v_mode = 'free' THEN RETURN true; END IF;

  IF v_mode = 'linear' THEN
    SELECT NOT EXISTS (
      SELECT 1 FROM chapters ch
      WHERE ch.course_id = v_course
        AND NOT ch.is_optional
        AND ch.position < v_pos
        AND NOT fn_chapter_completed(p_user, ch.id)
    ) INTO v_ok;
    RETURN v_ok;
  END IF;

  SELECT NOT EXISTS (SELECT 1 FROM chapter_prerequisites WHERE target_chapter_id = p_chapter)
      OR EXISTS (
           SELECT 1 FROM chapter_prerequisites cp
           WHERE cp.target_chapter_id = p_chapter
           GROUP BY cp.group_index
           HAVING bool_and(fn_chapter_completed(p_user, cp.source_chapter_id))
         )
    INTO v_ok;

  RETURN v_ok;
END;
$$;

-- ---------------------------------------------------------------------------
-- Courses — intrinsic prerequisites (roadmap-independent).
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_course_completed(p_user uuid, p_course uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM course_enrollments ce
    WHERE ce.user_id = p_user AND ce.course_id = p_course AND ce.status = 'completed'
  );
$$;

CREATE FUNCTION fn_course_available(p_user uuid, p_course uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM course_prerequisites WHERE target_course_id = p_course)
      OR EXISTS (
           SELECT 1 FROM course_prerequisites cp
           WHERE cp.target_course_id = p_course
           GROUP BY cp.group_index
           HAVING bool_and(fn_course_completed(p_user, cp.source_course_id))
         );
$$;

-- ---------------------------------------------------------------------------
-- Roadmap courses — this roadmap's chosen sequence, evaluated against the learner's
-- roadmap enrolment mode. Independent of the intrinsic course prerequisites above;
-- a caller that wants both should AND them together.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_roadmap_course_available(p_user uuid, p_roadmap_course uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_roadmap uuid;
  v_pos     integer;
  v_mode    progression_mode;
  v_ok      boolean;
BEGIN
  SELECT rc.roadmap_id, rc.position INTO v_roadmap, v_pos
  FROM roadmap_courses rc WHERE rc.id = p_roadmap_course;

  IF v_roadmap IS NULL THEN RETURN false; END IF;

  SELECT COALESCE(re.mode_override, r.progression_mode) INTO v_mode
  FROM roadmaps r
  LEFT JOIN roadmap_enrollments re ON re.roadmap_id = r.id AND re.user_id = p_user
  WHERE r.id = v_roadmap;

  IF v_mode = 'free' THEN RETURN true; END IF;

  IF v_mode = 'linear' THEN
    SELECT NOT EXISTS (
      SELECT 1 FROM roadmap_courses rc
      WHERE rc.roadmap_id = v_roadmap
        AND NOT rc.is_optional
        AND rc.position < v_pos
        AND NOT fn_course_completed(p_user, rc.course_id)
    ) INTO v_ok;
    RETURN v_ok;
  END IF;

  SELECT NOT EXISTS (
           SELECT 1 FROM roadmap_course_prerequisites
           WHERE target_roadmap_course_id = p_roadmap_course
         )
      OR EXISTS (
           SELECT 1
           FROM roadmap_course_prerequisites rcp
           JOIN roadmap_courses src ON src.id = rcp.source_roadmap_course_id
           WHERE rcp.target_roadmap_course_id = p_roadmap_course
           GROUP BY rcp.group_index
           HAVING bool_and(fn_course_completed(p_user, src.course_id))
         )
    INTO v_ok;

  RETURN v_ok;
END;
$$;

-- ---------------------------------------------------------------------------
-- Exercises within a set. This is the constrained/unconstrained toggle from brief §7:
-- the learner's per-set override decides whether the same edges are enforced.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_exercise_available(p_user uuid, p_set uuid, p_exercise uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_mode progression_mode;
  v_pos  integer;
  v_ok   boolean;
BEGIN
  SELECT COALESCE(ese.progression_mode_override, es.progression_mode)
    INTO v_mode
  FROM exercise_sets es
  LEFT JOIN exercise_set_enrollments ese
         ON ese.set_id = es.id AND ese.user_id = p_user
  WHERE es.id = p_set;

  IF v_mode IS NULL THEN RETURN false; END IF;   -- unknown set
  IF v_mode = 'free' THEN RETURN true;  END IF;

  IF v_mode = 'linear' THEN
    SELECT position INTO v_pos
    FROM exercise_set_items WHERE set_id = p_set AND exercise_id = p_exercise;

    IF v_pos IS NULL THEN RETURN false; END IF;

    SELECT NOT EXISTS (
      SELECT 1 FROM exercise_set_items esi
      WHERE esi.set_id = p_set
        AND esi.position < v_pos
        AND NOT EXISTS (
          SELECT 1 FROM exercise_progress ep
          WHERE ep.user_id = p_user AND ep.exercise_id = esi.exercise_id AND ep.status = 'solved'
        )
    ) INTO v_ok;
    RETURN v_ok;
  END IF;

  SELECT NOT EXISTS (
           SELECT 1 FROM exercise_prerequisites
           WHERE set_id = p_set AND target_exercise_id = p_exercise
         )
      OR EXISTS (
           SELECT 1 FROM exercise_prerequisites ep
           WHERE ep.set_id = p_set AND ep.target_exercise_id = p_exercise
           GROUP BY ep.group_index
           HAVING bool_and(EXISTS (
             SELECT 1 FROM exercise_progress x
             WHERE x.user_id = p_user
               AND x.exercise_id = ep.source_exercise_id
               AND x.status = 'solved'
           ))
         )
    INTO v_ok;

  RETURN v_ok;
END;
$$;

COMMIT;
