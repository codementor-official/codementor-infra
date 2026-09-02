-- Append the in-app preference to the existing read contract; email flags remain independent.
CREATE OR REPLACE VIEW notification_recipient_context AS
 SELECT u.id,u.external_id::text,u.email::text,u.display_name,u.timezone,u.status::text,u.email_verified_at,
   COALESCE(s.email_notifications,true) AS email_enabled,COALESCE(s.learning_reminders,true) AS learning_enabled,
   COALESCE(s.email_preferences,'{}'::jsonb) AS preferences,
   COALESCE(s.workspace_notifications,true) AS workspace_enabled
 FROM users u LEFT JOIN user_settings s ON s.user_id=u.id;
-- statement-breakpoint
-- Email learning opt-out must not disable the separately opted-in in-app study calendar.
CREATE OR REPLACE VIEW notification_study_schedule_context AS
 SELECT s.user_id,s.weekday::text AS weekday,s.start_time,s.duration_minutes,
   COALESCE(tz.name,'Asia/Ho_Chi_Minh') AS timezone
 FROM study_schedule_slots s JOIN learning_preferences p ON p.user_id=s.user_id
 JOIN notification_recipient_context u ON u.id=s.user_id
 LEFT JOIN pg_timezone_names tz ON tz.name=u.timezone
 WHERE s.enabled AND p.reminders_enabled AND u.status='active' AND u.external_id IS NOT NULL;
-- statement-breakpoint
CREATE OR REPLACE VIEW notification_workspace_member_context AS
 SELECT m.id,m.group_id,m.user_id,m.role::text,m.status::text,u.external_id::text,u.display_name,
   (m.role='owner' OR COALESCE(vo.allowed,vr.allowed,true)) AS can_view_doc,
   (m.role='owner' OR COALESCE(ao.allowed,ar.allowed,m.role='deputy')) AS can_approve_doc
 FROM group_members m JOIN users u ON u.id=m.user_id AND u.status='active'
 LEFT JOIN group_member_permissions vo ON vo.group_member_id=m.id AND vo.permission='view_doc'
 LEFT JOIN group_role_permissions vr ON vr.group_id=m.group_id AND vr.role=m.role AND vr.permission='view_doc'
 LEFT JOIN group_member_permissions ao ON ao.group_member_id=m.id AND ao.permission='approve_doc'
 LEFT JOIN group_role_permissions ar ON ar.group_id=m.group_id AND ar.role=m.role AND ar.permission='approve_doc';
-- statement-breakpoint
CREATE OR REPLACE VIEW notification_workspace_document_context AS
 SELECT d.id,d.group_id,d.title,d.status::text,d.uploader_id,d.reviewed_by,d.deleted_at,
   g.name AS workspace_name,g.slug::text AS workspace_slug
 FROM group_documents d JOIN study_groups g ON g.id=d.group_id AND g.status='active';
-- statement-breakpoint
CREATE OR REPLACE VIEW notification_workspace_activity_context AS
 SELECT id,name,slug::text FROM study_groups WHERE status='active';
-- statement-breakpoint
CREATE OR REPLACE VIEW notification_workspace_join_request_context AS
 SELECT id,group_id,user_id,status::text FROM workspace_join_requests;
-- statement-breakpoint
-- Events commit atomically with source changes. No historical backfill; no dependence on AI analysis.
CREATE OR REPLACE FUNCTION enqueue_workspace_activity_notification() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d jsonb; old_d jsonb; action text; actor text; kind text := TG_ARGV[0];
 event_id uuid := gen_random_uuid(); gid text; eid text; target_user text; payload jsonb;
BEGIN
 d := CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 old_d := CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) ELSE '{}'::jsonb END;
 gid:=d->>'group_id'; eid:=d->>'id';
 IF kind='DOCUMENT' THEN
   IF d->>'deleted_at' IS NOT NULL THEN RETURN COALESCE(NEW,OLD); END IF;
   IF TG_OP='INSERT' AND d->>'status'='pending' THEN
     -- Owner upload is auto-published immediately by workspace-service.
     IF EXISTS(SELECT 1 FROM group_members WHERE group_id=gid::uuid AND user_id=(d->>'uploader_id')::uuid AND role='owner') THEN RETURN NEW; END IF;
     action:='document_pending'; actor:=d->>'uploader_id';
   ELSIF d->>'status'='published' AND (TG_OP='INSERT' OR old_d->>'status'<>'published') THEN
     action:='document_published'; actor:=COALESCE(d->>'reviewed_by',d->>'uploader_id');
   ELSIF TG_OP='UPDATE' AND old_d->>'status'='pending' AND d->>'status'='hidden' THEN
     action:='document_rejected'; actor:=d->>'reviewed_by';
   ELSE RETURN COALESCE(NEW,OLD); END IF;
 ELSIF kind='MEMBER' THEN
   target_user:=d->>'user_id';
   IF d->>'role'='owner' AND TG_OP='INSERT' THEN RETURN NEW; END IF;
   IF TG_OP='DELETE' AND d->>'status'='active' THEN action:='member_left';
   ELSIF d->>'status'='active' AND (TG_OP='INSERT' OR old_d->>'status'<>'active') THEN action:='member_joined';
   ELSIF TG_OP='UPDATE' AND old_d->>'status'='active' AND d->>'status'<>'active' THEN action:='member_left';
   ELSIF TG_OP='UPDATE' AND d->>'status'='active' AND old_d->>'role'<>d->>'role' THEN action:='member_role_changed';
   ELSE RETURN COALESCE(NEW,OLD); END IF;
 ELSIF kind='JOIN_REQUEST' THEN
   IF d->>'status'<>'pending' OR (TG_OP='UPDATE' AND old_d->>'status'='pending') THEN RETURN COALESCE(NEW,OLD); END IF;
   action:='join_requested'; target_user:=d->>'user_id'; actor:=target_user;
 ELSE RETURN COALESCE(NEW,OLD); END IF;
 payload:=jsonb_build_object('groupId',gid,'entityId',eid,'action',action,'actorUserId',actor,'memberUserId',target_user,'role',d->>'role');
 INSERT INTO outbox(id,topic,partition_key,payload) VALUES(event_id,'evt.workspace.activity.v1',gid,
   jsonb_build_object('eventId',event_id,'eventName','evt.workspace.activity.v1','occurredAt',now(),
    'correlationId',event_id,'producer','workspace-service','payload',payload));
 RETURN COALESCE(NEW,OLD);
END $$;
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_document_notification ON group_documents;
-- statement-breakpoint
CREATE TRIGGER trg_document_notification AFTER INSERT OR UPDATE ON group_documents
 FOR EACH ROW EXECUTE FUNCTION enqueue_workspace_activity_notification('DOCUMENT');
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_member_notification ON group_members;
-- statement-breakpoint
CREATE TRIGGER trg_member_notification AFTER INSERT OR UPDATE OR DELETE ON group_members
 FOR EACH ROW EXECUTE FUNCTION enqueue_workspace_activity_notification('MEMBER');
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_join_request_notification ON workspace_join_requests;
-- statement-breakpoint
CREATE TRIGGER trg_join_request_notification AFTER INSERT OR UPDATE ON workspace_join_requests
 FOR EACH ROW EXECUTE FUNCTION enqueue_workspace_activity_notification('JOIN_REQUEST');
-- statement-breakpoint
CREATE OR REPLACE FUNCTION enqueue_assignment_review_notification() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE event_id uuid := gen_random_uuid();
BEGIN
 IF NEW.review_status IS NOT DISTINCT FROM OLD.review_status OR NEW.review_status NOT IN ('approved','needsfix')
   OR NEW.reviewed_by IS NULL THEN RETURN NEW; END IF;
 INSERT INTO outbox(id,topic,partition_key,payload) VALUES(event_id,'evt.assignment.reviewed.v1',NEW.group_id::text,
  jsonb_build_object('eventId',event_id,'eventName','evt.assignment.reviewed.v1','occurredAt',now(),
   'correlationId',event_id,'producer','workspace-service','payload',jsonb_build_object(
    'groupId',NEW.group_id,'assignmentId',NEW.id,'memberId',NEW.member_id,
    'reviewStatus',NEW.review_status,'reviewedBy',NEW.reviewed_by)));
 RETURN NEW;
END $$;
-- statement-breakpoint
DROP TRIGGER IF EXISTS trg_assignment_review_notification ON assignments;
-- statement-breakpoint
CREATE TRIGGER trg_assignment_review_notification AFTER UPDATE ON assignments
 FOR EACH ROW EXECUTE FUNCTION enqueue_assignment_review_notification();
