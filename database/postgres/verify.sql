-- Verification suite. Run against a migrated + seeded database:
--     psql -v ON_ERROR_STOP=1 -f postgres/verify.sql
--
-- Every check RAISEs on failure, so a non-zero exit means the model is broken.
-- Wrapped in a transaction and rolled back: the negative tests insert deliberately invalid
-- rows and must not leave anything behind.

BEGIN;

\echo '== A. derived caches match their source of truth =='

DO $$
DECLARE r record; expected integer;
BEGIN
  FOR r IN SELECT * FROM course_enrollments LOOP
    SELECT count(*) INTO expected
    FROM lessons l
    JOIN lesson_progress lp ON lp.lesson_id = l.id
    WHERE l.course_id = r.course_id AND lp.user_id = r.user_id
      AND lp.status = 'completed' AND NOT l.is_optional;

    IF expected <> r.completed_lessons THEN
      RAISE EXCEPTION 'course_enrollments cache drift: user=% course=% cached=% actual=%',
        r.user_id, r.course_id, r.completed_lessons, expected;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS  course progress cache';
END $$;

DO $$
DECLARE r record; expected integer;
BEGIN
  FOR r IN SELECT * FROM roadmap_enrollments LOOP
    SELECT count(*) INTO expected
    FROM roadmap_courses rc
    JOIN course_enrollments ce ON ce.course_id = rc.course_id AND ce.user_id = r.user_id
    WHERE rc.roadmap_id = r.roadmap_id AND NOT rc.is_optional AND ce.status = 'completed';

    IF expected <> r.completed_courses THEN
      RAISE EXCEPTION 'roadmap_enrollments cache drift: user=% roadmap=% cached=% actual=%',
        r.user_id, r.roadmap_id, r.completed_courses, expected;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS  roadmap progress cache';
END $$;

DO $$
DECLARE bad integer;
BEGIN
  SELECT count(*) INTO bad
  FROM courses c
  WHERE c.total_lessons  <> (SELECT count(*) FROM lessons  l  WHERE l.course_id  = c.id)
     OR c.total_chapters <> (SELECT count(*) FROM chapters ch WHERE ch.course_id = c.id);
  IF bad > 0 THEN RAISE EXCEPTION 'curriculum counters drifted on % course(s)', bad; END IF;
  RAISE NOTICE 'PASS  curriculum counters';
END $$;

\echo ''
\echo '== B. availability resolution =='

DO $$
DECLARE
  giasi uuid := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  -- BRANCHING: L1 done → L4 open (L4 requires only L1)
  IF NOT fn_lesson_available(giasi, 'f0000000-0000-4000-8000-000000000004') THEN
    RAISE EXCEPTION 'branching: L4 should be available after L1';
  END IF;

  -- AND JOIN: L5 requires L2 AND L3, both done → open
  IF NOT fn_lesson_available(giasi, 'f0000000-0000-4000-8000-000000000005') THEN
    RAISE EXCEPTION 'AND join: L5 should be available once L2 and L3 are complete';
  END IF;

  -- L6 requires L5, which is not complete → closed
  IF fn_lesson_available(giasi, 'f0000000-0000-4000-8000-000000000006') THEN
    RAISE EXCEPTION 'L6 should still be locked (L5 incomplete)';
  END IF;

  -- LINEAR mode: first lesson open, second closed until the first is done
  IF NOT fn_lesson_available(giasi, 'f0000000-0000-4000-8000-000000000012') THEN
    RAISE EXCEPTION 'linear: first lesson must be available';
  END IF;
  IF fn_lesson_available(giasi, 'f0000000-0000-4000-8000-000000000013') THEN
    RAISE EXCEPTION 'linear: second lesson must be locked before the first is completed';
  END IF;

  RAISE NOTICE 'PASS  availability (branching, AND join, linear)';
END $$;

\echo ''
\echo '== C. dependency guards reject invalid graphs =='

-- helper: assert that a statement fails with a given SQLSTATE
CREATE FUNCTION pg_temp.expect_failure(p_sql text, p_label text, p_state text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION
    WHEN others THEN
      IF p_state IS NOT NULL AND SQLSTATE <> p_state THEN
        RAISE EXCEPTION 'FAIL % — expected SQLSTATE %, got % (%)', p_label, p_state, SQLSTATE, SQLERRM;
      END IF;
      RAISE NOTICE 'PASS  % (%)', p_label, SQLSTATE;
      RETURN;
  END;
  RAISE EXCEPTION 'FAIL % — the invalid statement was accepted', p_label;
END $$;

-- self reference
SELECT pg_temp.expect_failure($$
  INSERT INTO lesson_prerequisites (course_id, target_lesson_id, source_lesson_id)
  VALUES ('c0000000-0000-4000-8000-000000000001',
          'f0000000-0000-4000-8000-000000000002','f0000000-0000-4000-8000-000000000002')
$$, 'self-reference rejected', '23514');

-- duplicate edge
SELECT pg_temp.expect_failure($$
  INSERT INTO lesson_prerequisites (course_id, target_lesson_id, source_lesson_id, group_index)
  VALUES ('c0000000-0000-4000-8000-000000000001',
          'f0000000-0000-4000-8000-000000000002','f0000000-0000-4000-8000-000000000001',0)
$$, 'duplicate edge rejected', '23505');

-- direct cycle: L1 already precedes L2, so L2 → L1 closes a loop
SELECT pg_temp.expect_failure($$
  INSERT INTO lesson_prerequisites (course_id, target_lesson_id, source_lesson_id)
  VALUES ('c0000000-0000-4000-8000-000000000001',
          'f0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000002')
$$, 'direct cycle rejected', '23514');

-- indirect cycle: L1 → L2 → L5 → L6 exists, so L6 → L1 closes it
SELECT pg_temp.expect_failure($$
  INSERT INTO lesson_prerequisites (course_id, target_lesson_id, source_lesson_id)
  VALUES ('c0000000-0000-4000-8000-000000000001',
          'f0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000006')
$$, 'indirect cycle rejected', '23514');

-- cross-course edge: an HTML lesson cannot gate a Java Core lesson
SELECT pg_temp.expect_failure($$
  INSERT INTO lesson_prerequisites (course_id, target_lesson_id, source_lesson_id)
  VALUES ('c0000000-0000-4000-8000-000000000001',
          'f0000000-0000-4000-8000-000000000004','f0000000-0000-4000-8000-000000000010')
$$, 'cross-course edge rejected', '23503');

-- missing entity
SELECT pg_temp.expect_failure($$
  INSERT INTO lesson_prerequisites (course_id, target_lesson_id, source_lesson_id)
  VALUES ('c0000000-0000-4000-8000-000000000001',
          'f0000000-0000-4000-8000-000000000004','f0000000-0000-4000-8000-0000000000ff')
$$, 'missing entity rejected', '23503');

-- deleting a course a roadmap still uses must fail loudly.
-- ON DELETE RESTRICT raises 23001 (restrict_violation), not 23503.
SELECT pg_temp.expect_failure($$
  DELETE FROM courses WHERE id = 'c0000000-0000-4000-8000-000000000001'
$$, 'RESTRICT protects referenced course', '23001');

\echo ''
\echo '== D. structural invariants =='

DO $$
DECLARE bad integer;
BEGIN
  SELECT count(*) INTO bad FROM lessons l
  JOIN chapters ch ON ch.id = l.chapter_id
  WHERE l.course_id <> ch.course_id;
  IF bad > 0 THEN RAISE EXCEPTION 'denormalised lessons.course_id drifted on % row(s)', bad; END IF;

  SELECT count(*) INTO bad FROM study_groups g
  WHERE (SELECT count(*) FROM group_members m WHERE m.group_id = g.id AND m.role = 'owner') <> 1;
  IF bad > 0 THEN RAISE EXCEPTION '% group(s) do not have exactly one owner', bad; END IF;

  RAISE NOTICE 'PASS  structural invariants';
END $$;

\echo ''
\echo 'ALL CHECKS PASSED'

ROLLBACK;
