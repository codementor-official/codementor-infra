-- 0049 — "roadmap completed" email (backend ADR 0005, phase 4).
--
-- Reuses enqueue_reminder_source_change() from 0026 unchanged. The WHEN clause limits the event
-- to the moment a roadmap enrollment BECOMES completed: fn_refresh_roadmap_progress rewrites
-- last_activity_at on every lesson, and an event per lesson would be pure noise.
BEGIN;

DROP TRIGGER IF EXISTS trg_roadmap_reminder_source ON roadmap_enrollments;
CREATE TRIGGER trg_roadmap_reminder_source
  AFTER UPDATE ON roadmap_enrollments
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION enqueue_reminder_source_change('ROADMAP', 'learning-service');

COMMIT;
