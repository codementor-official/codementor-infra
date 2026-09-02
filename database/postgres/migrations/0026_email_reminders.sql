-- Notification-owned queues; no business service sends email.
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS email_preferences jsonb NOT NULL DEFAULT '{}';
-- statement-breakpoint
CREATE TABLE IF NOT EXISTS notification_reminders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 type text NOT NULL, category text NOT NULL,
 entity_type text NOT NULL, entity_id text NOT NULL,
 dedupe_key text NOT NULL UNIQUE, source_version text,
 scheduled_at timestamptz NOT NULL, status text NOT NULL DEFAULT 'PENDING'
   CHECK (status IN ('PENDING','PROCESSING','SENT','FAILED','CANCELLED')),
 payload jsonb NOT NULL, sent_at timestamptz, cancelled_at timestamptz,
 retry_count integer NOT NULL DEFAULT 0 CHECK (retry_count BETWEEN 0 AND 3),
 retryable boolean NOT NULL DEFAULT true,
 processing_token uuid, locked_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
-- statement-breakpoint
CREATE INDEX IF NOT EXISTS idx_notification_reminders_due ON notification_reminders(scheduled_at)
 WHERE status IN ('PENDING','FAILED') AND retryable;
-- statement-breakpoint
CREATE INDEX IF NOT EXISTS idx_notification_reminders_entity ON notification_reminders(entity_type,entity_id,user_id);
-- statement-breakpoint
CREATE INDEX IF NOT EXISTS idx_notification_reminders_user ON notification_reminders(user_id,created_at DESC,id DESC);
-- statement-breakpoint
CREATE TABLE IF NOT EXISTS email_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 notification_id text, reminder_id uuid NOT NULL UNIQUE REFERENCES notification_reminders(id) ON DELETE CASCADE,
 recipient text NOT NULL, template text NOT NULL,
 status text NOT NULL CHECK (status IN ('PROCESSING','SENT','FAILED','SKIPPED','UNKNOWN')),
 provider_message_id text, error_message text, attempt_count integer NOT NULL DEFAULT 0,
 sent_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
-- statement-breakpoint
CREATE INDEX IF NOT EXISTS idx_email_deliveries_rate ON email_deliveries(updated_at DESC) WHERE status<>'SKIPPED';
-- statement-breakpoint
-- Explicit read-only contracts for notification-service; it never mutates source tables.
CREATE OR REPLACE VIEW notification_recipient_context AS
 SELECT u.id, u.external_id::text, u.email::text, u.display_name, u.timezone, u.status::text,
        u.email_verified_at,
        COALESCE(s.email_notifications,true) AS email_enabled,
        COALESCE(s.learning_reminders,true) AS learning_enabled,
        COALESCE(s.email_preferences,'{}'::jsonb) AS preferences,
        COALESCE(s.workspace_notifications,true) AS workspace_enabled
 FROM users u LEFT JOIN user_settings s ON s.user_id=u.id;
-- statement-breakpoint
CREATE OR REPLACE VIEW notification_assignment_context AS
 SELECT a.id, m.user_id, a.group_id, a.group_exercise_id, m.id AS member_id,
        g.slug::text AS workspace_slug, g.name AS workspace_name, e.title AS exercise_title,
        ge.exercise_id, ge.due_at, ge.allow_retry,
        a.status::text, a.review_status::text,
        (a.review_status<>'needsfix' AND (a.status='done' OR EXISTS (SELECT 1 FROM submissions s WHERE s.assignment_id=a.id AND s.verdict='accepted'))) AS completed,
        (g.status='active' AND m.status='active' AND ge.deleted_at IS NULL AND ge.publication_status='published') AS eligible
 FROM assignments a JOIN group_members m ON m.id=a.member_id
 JOIN group_exercises ge ON ge.id=a.group_exercise_id
 JOIN study_groups g ON g.id=a.group_id JOIN exercises e ON e.id=ge.exercise_id;
-- statement-breakpoint
CREATE OR REPLACE VIEW notification_learning_context AS
 SELECT ce.id,ce.user_id,ce.course_id, c.title,ce.status::text,
 COALESCE(ce.last_activity_at,ce.started_at) AS last_activity_at,
 (c.status='published') AS eligible
 FROM course_enrollments ce JOIN courses c ON c.id=ce.course_id;
-- statement-breakpoint
CREATE OR REPLACE VIEW notification_workspace_context AS
 SELECT m.id,m.user_id,g.id AS group_id,g.slug::text,g.name,m.role::text,m.status::text
 FROM group_members m JOIN study_groups g ON g.id=m.group_id WHERE g.status='active';
-- statement-breakpoint
-- Reuse the existing transactional outbox. The change event commits atomically
-- with assignments, submission verdicts and enrollment progress, including SQL-trigger updates.
CREATE OR REPLACE FUNCTION enqueue_reminder_source_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE row_data jsonb; old_data jsonb; event_id uuid := gen_random_uuid();
 source_kind text := TG_ARGV[0]; entity_id text; producer_name text := TG_ARGV[1];
 change_kind text := TG_OP; extra jsonb := '{}'::jsonb;
BEGIN
 row_data := CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF TG_OP='UPDATE' THEN
   old_data := to_jsonb(OLD);
   IF source_kind='SUBMISSION' AND old_data->'verdict'=row_data->'verdict' THEN RETURN NEW; END IF;
   IF source_kind='COURSE' AND old_data->'last_activity_at' IS NOT DISTINCT FROM row_data->'last_activity_at'
      AND old_data->'status'=row_data->'status' THEN RETURN NEW; END IF;
   IF source_kind='GROUP_EXERCISE' AND old_data->'due_at' IS NOT DISTINCT FROM row_data->'due_at'
      AND old_data->'publication_status'=row_data->'publication_status'
      AND old_data->'deleted_at' IS NOT DISTINCT FROM row_data->'deleted_at' THEN RETURN NEW; END IF;
 END IF;
 entity_id := row_data->>'id';
 IF source_kind='SETTINGS' THEN
   entity_id := row_data->>'user_id';
   IF TG_OP='UPDATE' AND old_data->'email_preferences' IS NOT DISTINCT FROM row_data->'email_preferences'
      AND old_data->'learning_reminders'=row_data->'learning_reminders' THEN RETURN NEW; END IF;
 END IF;
 IF source_kind='GROUP_EXERCISE' AND TG_OP='UPDATE' THEN
   extra := jsonb_build_object('deadlineChanged',old_data->'due_at' IS DISTINCT FROM row_data->'due_at');
 END IF;
 IF source_kind='SUBMISSION' THEN
   IF row_data->>'assignment_id' IS NULL OR row_data->>'verdict'='pending' THEN RETURN NEW; END IF;
   entity_id := row_data->>'assignment_id';
   extra := jsonb_build_object('submissionId',row_data->>'id','verdict',row_data->>'verdict');
 END IF;
 IF source_kind='MEMBERSHIP' AND TG_OP='INSERT' THEN
   -- Join approvals have their own semantic event; direct adds are announced here.
   IF EXISTS (SELECT 1 FROM workspace_join_requests WHERE group_id=(row_data->>'group_id')::uuid
              AND user_id=(row_data->>'user_id')::uuid AND status IN ('pending','approved')) THEN
     change_kind := 'SYNC';
   END IF;
 END IF;
 INSERT INTO outbox(id,topic,partition_key,payload)
 VALUES(event_id,'evt.reminder.source-changed.v1',entity_id,
 jsonb_build_object('eventId',event_id,'eventName','evt.reminder.source-changed.v1',
 'occurredAt',now(),'correlationId',event_id,'producer',producer_name,
 'payload',jsonb_build_object('entityType',source_kind,'entityId',entity_id,
 'change',change_kind,'changedAt',now()) || extra));
 RETURN COALESCE(NEW,OLD);
END $$;
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_assignment_reminder_source ON assignments;
-- statement-breakpoint
CREATE TRIGGER trg_assignment_reminder_source AFTER INSERT OR UPDATE OR DELETE ON assignments
 FOR EACH ROW EXECUTE FUNCTION enqueue_reminder_source_change('ASSIGNMENT','workspace-service');
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_group_exercise_reminder_source ON group_exercises;
-- statement-breakpoint
CREATE TRIGGER trg_group_exercise_reminder_source AFTER UPDATE ON group_exercises
 FOR EACH ROW EXECUTE FUNCTION enqueue_reminder_source_change('GROUP_EXERCISE','workspace-service');
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_submission_reminder_source ON submissions;
-- statement-breakpoint
CREATE TRIGGER trg_submission_reminder_source AFTER INSERT OR UPDATE ON submissions
 FOR EACH ROW EXECUTE FUNCTION enqueue_reminder_source_change('SUBMISSION','submission-service');
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_learning_reminder_source ON course_enrollments;
-- statement-breakpoint
CREATE TRIGGER trg_learning_reminder_source AFTER INSERT OR UPDATE OR DELETE ON course_enrollments
 FOR EACH ROW EXECUTE FUNCTION enqueue_reminder_source_change('COURSE','learning-service');
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_membership_reminder_source ON group_members;
-- statement-breakpoint
CREATE TRIGGER trg_membership_reminder_source AFTER INSERT OR UPDATE OR DELETE ON group_members
 FOR EACH ROW EXECUTE FUNCTION enqueue_reminder_source_change('MEMBERSHIP','workspace-service');
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_settings_reminder_source ON user_settings;
-- statement-breakpoint
CREATE TRIGGER trg_settings_reminder_source AFTER INSERT OR UPDATE OR DELETE ON user_settings
 FOR EACH ROW EXECUTE FUNCTION enqueue_reminder_source_change('SETTINGS','core-service');
