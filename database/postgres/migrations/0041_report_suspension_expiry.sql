-- 0041 — khoá tài khoản theo báo cáo vi phạm có thời hạn.
--
-- Additive, idempotent. CHẠY TRƯỚC core-service có `ReportModerationService.expireSuspensions`.
-- `suspended_until` NULL nghĩa là khoá tới khi có người mở (hành vi trước migration này).
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE content_report_actions ADD COLUMN IF NOT EXISTS suspended_until timestamptz;

-- Job mở khoá quét mỗi phút đúng các dòng này.
CREATE INDEX IF NOT EXISTS idx_content_report_actions_suspension_due
  ON content_report_actions (suspended_until)
  WHERE action = 'USER_SUSPENDED' AND reverted_at IS NULL AND suspended_until IS NOT NULL;

COMMIT;
