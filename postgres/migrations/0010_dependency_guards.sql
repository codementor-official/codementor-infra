-- 0010 — dependency graph integrity.
--
-- Already handled declaratively in 0006 and therefore NOT repeated here:
--   self-reference      CHECK (source <> target)
--   duplicate edge      PRIMARY KEY (target, source, group_index)
--   missing entity      FOREIGN KEY
--   cross-scope edge    composite FOREIGN KEY into (scope, id)
--   negative group      CHECK (group_index >= 0)
--
-- What is left needs graph traversal or a lookup, so it lives in triggers:
--   cycles (including indirect A→B→C→A)
--   prerequisites pointing at archived content

BEGIN;

-- ---------------------------------------------------------------------------
-- Generic cycle guard, parameterised by table/column names so all five edge tables
-- share one implementation.
--
-- Inserting "source S must precede target T" is illegal when T already precedes S,
-- directly or transitively. So: walk forward from T and see whether S is reachable.
-- UNION (not UNION ALL) makes the walk terminate even if bad data already contains a loop.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_prevent_dependency_cycle() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  tbl        text  := TG_ARGV[0];
  target_col text  := TG_ARGV[1];
  source_col text  := TG_ARGV[2];
  scope_col  text  := NULLIF(TG_ARGV[3], '');
  rec        jsonb := to_jsonb(NEW);
  v_target   uuid  := (rec ->> target_col)::uuid;
  v_source   uuid  := (rec ->> source_col)::uuid;
  v_scope    uuid;
  v_sql      text;
  v_cycle    boolean;
BEGIN
  IF scope_col IS NOT NULL THEN
    v_scope := (rec ->> scope_col)::uuid;
  END IF;

  v_sql := format($q$
    WITH RECURSIVE descendants(id) AS (
        SELECT $1::uuid
      UNION
        SELECT p.%I
        FROM %I p
        JOIN descendants d ON p.%I = d.id
        %s
    )
    SELECT EXISTS (SELECT 1 FROM descendants WHERE id = $2::uuid)
  $q$,
    target_col,
    tbl,
    source_col,
    CASE WHEN scope_col IS NULL THEN '' ELSE format('WHERE p.%I = $3::uuid', scope_col) END
  );

  IF scope_col IS NULL THEN
    EXECUTE v_sql INTO v_cycle USING v_target, v_source;
  ELSE
    EXECUTE v_sql INTO v_cycle USING v_target, v_source, v_scope;
  END IF;

  IF v_cycle THEN
    RAISE EXCEPTION
      'circular dependency: adding %(source=%, target=%) would close a cycle',
      tbl, v_source, v_target
      USING ERRCODE = 'check_violation',
            HINT = 'The target already precedes the source, directly or transitively.';
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_rcp_no_cycle
  BEFORE INSERT OR UPDATE ON roadmap_course_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_prevent_dependency_cycle(
    'roadmap_course_prerequisites', 'target_roadmap_course_id', 'source_roadmap_course_id', 'roadmap_id');

CREATE TRIGGER trg_cp_no_cycle
  BEFORE INSERT OR UPDATE ON course_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_prevent_dependency_cycle(
    'course_prerequisites', 'target_course_id', 'source_course_id', '');

CREATE TRIGGER trg_chp_no_cycle
  BEFORE INSERT OR UPDATE ON chapter_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_prevent_dependency_cycle(
    'chapter_prerequisites', 'target_chapter_id', 'source_chapter_id', 'course_id');

CREATE TRIGGER trg_lp_no_cycle
  BEFORE INSERT OR UPDATE ON lesson_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_prevent_dependency_cycle(
    'lesson_prerequisites', 'target_lesson_id', 'source_lesson_id', 'course_id');

CREATE TRIGGER trg_ep_no_cycle
  BEFORE INSERT OR UPDATE ON exercise_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_prevent_dependency_cycle(
    'exercise_prerequisites', 'target_exercise_id', 'source_exercise_id', 'set_id');

-- ---------------------------------------------------------------------------
-- Archived content must not appear in a live dependency graph — it would gate a learner
-- behind something they can no longer open.
-- Only entities that actually carry a lifecycle status are checked; chapters and lessons
-- inherit their course's status, so checking them would be redundant.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_reject_archived_course_edge() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  bad text;
BEGIN
  SELECT c.slug INTO bad
  FROM courses c
  WHERE c.id IN (NEW.source_course_id, NEW.target_course_id)
    AND c.status = 'archived'
  LIMIT 1;

  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'course prerequisite references archived course "%"', bad
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cp_no_archived
  BEFORE INSERT OR UPDATE ON course_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_reject_archived_course_edge();

CREATE FUNCTION fn_reject_archived_roadmap_course_edge() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  bad text;
BEGIN
  SELECT c.slug INTO bad
  FROM roadmap_courses rc
  JOIN courses c ON c.id = rc.course_id
  WHERE rc.id IN (NEW.source_roadmap_course_id, NEW.target_roadmap_course_id)
    AND c.status = 'archived'
  LIMIT 1;

  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'roadmap course prerequisite references archived course "%"', bad
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_rcp_no_archived
  BEFORE INSERT OR UPDATE ON roadmap_course_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_reject_archived_roadmap_course_edge();

CREATE FUNCTION fn_reject_archived_exercise_edge() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  bad text;
BEGIN
  SELECT e.slug INTO bad
  FROM exercises e
  WHERE e.id IN (NEW.source_exercise_id, NEW.target_exercise_id)
    AND e.status IN ('archived', 'rejected')
  LIMIT 1;

  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'exercise prerequisite references retired exercise "%"', bad
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ep_no_archived
  BEFORE INSERT OR UPDATE ON exercise_prerequisites
  FOR EACH ROW EXECUTE FUNCTION fn_reject_archived_exercise_edge();

COMMIT;
