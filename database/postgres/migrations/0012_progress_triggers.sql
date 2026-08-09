-- 0012 — keep the derived progress caches honest.
--
-- lesson_progress is the source of truth. Everything below is a materialised count whose
-- invariant is stated in docs/01-domain-model.md §3.1 and re-checked by scripts/verify.sql.
-- The application never writes these columns.

BEGIN;

-- ---------------------------------------------------------------------------
-- Course enrolment cache
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_refresh_course_progress(p_user uuid, p_course uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_total     integer;
  v_done      integer;
  v_percent   numeric(5,2);
BEGIN
  SELECT count(*) FILTER (WHERE NOT l.is_optional)
    INTO v_total
  FROM lessons l WHERE l.course_id = p_course;

  SELECT count(*)
    INTO v_done
  FROM lessons l
  JOIN lesson_progress lp ON lp.lesson_id = l.id
  WHERE l.course_id = p_course
    AND lp.user_id = p_user
    AND lp.status = 'completed'
    AND NOT l.is_optional;

  v_percent := CASE WHEN COALESCE(v_total, 0) = 0 THEN 0
                    ELSE round((v_done::numeric * 100) / v_total, 2) END;

  UPDATE course_enrollments ce
     SET completed_lessons = v_done,
         progress_percent  = v_percent,
         last_activity_at  = now(),
         status       = CASE WHEN v_total > 0 AND v_done >= v_total THEN 'completed'::enrollment_status
                             WHEN ce.status = 'completed' THEN 'active'::enrollment_status
                             ELSE ce.status END,
         completed_at = CASE WHEN v_total > 0 AND v_done >= v_total THEN COALESCE(ce.completed_at, now())
                             ELSE NULL END
   WHERE ce.user_id = p_user AND ce.course_id = p_course;
END;
$$;

-- ---------------------------------------------------------------------------
-- Roadmap enrolment cache — counts completed course enrolments within the roadmap.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_refresh_roadmap_progress(p_user uuid, p_roadmap uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_total   integer;
  v_done    integer;
  v_percent numeric(5,2);
BEGIN
  SELECT count(*) FILTER (WHERE NOT rc.is_optional)
    INTO v_total
  FROM roadmap_courses rc WHERE rc.roadmap_id = p_roadmap;

  SELECT count(*)
    INTO v_done
  FROM roadmap_courses rc
  JOIN course_enrollments ce ON ce.course_id = rc.course_id AND ce.user_id = p_user
  WHERE rc.roadmap_id = p_roadmap
    AND NOT rc.is_optional
    AND ce.status = 'completed';

  v_percent := CASE WHEN COALESCE(v_total, 0) = 0 THEN 0
                    ELSE round((v_done::numeric * 100) / v_total, 2) END;

  UPDATE roadmap_enrollments re
     SET completed_courses = v_done,
         progress_percent  = v_percent,
         last_activity_at  = now(),
         status       = CASE WHEN v_total > 0 AND v_done >= v_total THEN 'completed'::enrollment_status
                             WHEN re.status = 'completed' THEN 'active'::enrollment_status
                             ELSE re.status END,
         completed_at = CASE WHEN v_total > 0 AND v_done >= v_total THEN COALESCE(re.completed_at, now())
                             ELSE NULL END
   WHERE re.user_id = p_user AND re.roadmap_id = p_roadmap;
END;
$$;

-- ---------------------------------------------------------------------------
-- lesson_progress → course cache → every roadmap containing that course
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_on_lesson_progress_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_user   uuid := COALESCE(NEW.user_id, OLD.user_id);
  v_lesson uuid := COALESCE(NEW.lesson_id, OLD.lesson_id);
  v_course uuid;
  r        record;
BEGIN
  SELECT course_id INTO v_course FROM lessons WHERE id = v_lesson;
  IF v_course IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  PERFORM fn_refresh_course_progress(v_user, v_course);

  FOR r IN
    SELECT DISTINCT rc.roadmap_id
    FROM roadmap_courses rc
    JOIN roadmap_enrollments re
      ON re.roadmap_id = rc.roadmap_id AND re.user_id = v_user
    WHERE rc.course_id = v_course
  LOOP
    PERFORM fn_refresh_roadmap_progress(v_user, r.roadmap_id);
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_lesson_progress_refresh
  AFTER INSERT OR UPDATE OR DELETE ON lesson_progress
  FOR EACH ROW EXECUTE FUNCTION fn_on_lesson_progress_change();

-- ---------------------------------------------------------------------------
-- Denormalised counters that the browse grids read on every card.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_on_course_enrollment_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE courses c
     SET enrollment_count = (SELECT count(*) FROM course_enrollments ce WHERE ce.course_id = c.id)
   WHERE c.id = COALESCE(NEW.course_id, OLD.course_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_course_enrollment_count
  AFTER INSERT OR DELETE ON course_enrollments
  FOR EACH ROW EXECUTE FUNCTION fn_on_course_enrollment_change();

CREATE FUNCTION fn_on_course_review_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_course uuid := COALESCE(NEW.course_id, OLD.course_id);
BEGIN
  UPDATE courses c
     SET rating_count = (SELECT count(*)      FROM course_reviews r WHERE r.course_id = v_course),
         rating_avg   = (SELECT round(avg(r.rating), 2) FROM course_reviews r WHERE r.course_id = v_course)
   WHERE c.id = v_course;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_course_rating_refresh
  AFTER INSERT OR UPDATE OR DELETE ON course_reviews
  FOR EACH ROW EXECUTE FUNCTION fn_on_course_review_change();

CREATE FUNCTION fn_on_curriculum_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_course uuid;
BEGIN
  IF TG_TABLE_NAME = 'chapters' THEN
    v_course := COALESCE(NEW.course_id, OLD.course_id);
  ELSE
    v_course := COALESCE(NEW.course_id, OLD.course_id);
  END IF;

  UPDATE courses c
     SET total_chapters = (SELECT count(*) FROM chapters ch WHERE ch.course_id = v_course),
         total_lessons  = (SELECT count(*) FROM lessons  l  WHERE l.course_id  = v_course)
   WHERE c.id = v_course;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_chapters_curriculum_count
  AFTER INSERT OR DELETE ON chapters
  FOR EACH ROW EXECUTE FUNCTION fn_on_curriculum_change();

CREATE TRIGGER trg_lessons_curriculum_count
  AFTER INSERT OR DELETE ON lessons
  FOR EACH ROW EXECUTE FUNCTION fn_on_curriculum_change();

CREATE FUNCTION fn_on_group_member_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_group uuid := COALESCE(NEW.group_id, OLD.group_id);
BEGIN
  UPDATE study_groups g
     SET member_count = (SELECT count(*) FROM group_members m
                          WHERE m.group_id = v_group AND m.status = 'active')
   WHERE g.id = v_group;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_group_member_count
  AFTER INSERT OR UPDATE OR DELETE ON group_members
  FOR EACH ROW EXECUTE FUNCTION fn_on_group_member_change();

COMMIT;
