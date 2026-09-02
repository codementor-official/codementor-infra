-- Read-only source contract: notification-service never writes personal preferences.
CREATE OR REPLACE VIEW notification_study_schedule_context AS
 SELECT s.user_id, s.weekday::text AS weekday, s.start_time, s.duration_minutes,
        COALESCE(tz.name, 'Asia/Ho_Chi_Minh') AS timezone
 FROM study_schedule_slots s
 JOIN learning_preferences p ON p.user_id=s.user_id
 JOIN notification_recipient_context u ON u.id=s.user_id
 LEFT JOIN pg_timezone_names tz ON tz.name=u.timezone
 WHERE s.enabled AND p.reminders_enabled AND u.learning_enabled
   AND u.status='active' AND u.external_id IS NOT NULL;
-- statement-breakpoint
-- Five-minute catch-up, including across local midnight. Never backfill old weeks.
-- PostgreSQL handles IANA offsets/DST; round-trip check skips nonexistent spring-forward times.
CREATE OR REPLACE FUNCTION notification_study_schedule_due(p_now timestamptz)
RETURNS TABLE(user_id uuid, weekday text, local_date date, start_time time,
              duration_minutes integer, timezone text, due_at timestamptz, version text)
LANGUAGE sql STABLE AS $$
 WITH candidates AS (
   SELECT s.*, ((p_now AT TIME ZONE s.timezone)::date - d.day_offset) AS local_date
   FROM notification_study_schedule_context s CROSS JOIN generate_series(0,1) d(day_offset)
 ), occurrences AS (
   SELECT c.*, (c.local_date+c.start_time) AT TIME ZONE c.timezone AS due_at
   FROM candidates c
   WHERE c.weekday=(ARRAY['mon','tue','wed','thu','fri','sat','sun'])[extract(isodow FROM c.local_date)::integer]
 )
 SELECT o.user_id,o.weekday,o.local_date,o.start_time,o.duration_minutes,o.timezone,o.due_at,
        o.local_date::text || 'T' || to_char(o.start_time,'HH24:MI') || '|' || o.timezone
 FROM occurrences o
 WHERE o.due_at<=p_now AND o.due_at>p_now-interval '5 minutes'
   AND (o.due_at AT TIME ZONE o.timezone)=(o.local_date+o.start_time)
$$;
