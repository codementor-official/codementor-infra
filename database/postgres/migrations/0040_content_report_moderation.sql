-- 0040 — xử lý báo cáo vi phạm có lịch sử và hoàn tác được; chặn gửi báo cáo dồn dập.
--
-- Additive, idempotent. CHẠY TRƯỚC khi deploy core-service có `ReportModerationService`:
-- bản đó đọc `submitted_at` và ghi `content_report_actions`.
--
-- 1. `resolution_note`, `resolved_by`, `resolved_at` vốn chỉ được tạo bởi
--    `codementor-backend/scripts/migrate-client-support.mjs`; một DB dựng chỉ từ repo này thiếu
--    chúng và trang báo cáo của admin trả 500. Thêm lại ở đây, IF NOT EXISTS nên DB đã có là no-op.
-- 2. `submitted_at`: lần cuối NGƯỜI BÁO CÁO gửi. Không dùng `updated_at` vì admin kết luận cũng
--    đổi cột đó — giới hạn 1 báo cáo / 10 phút sẽ phạt nhầm người vừa được admin trả lời.
-- 3. `content_report_actions`: mỗi thao tác của admin một dòng, đủ giá trị cũ để hoàn tác.

BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE content_reports ADD COLUMN IF NOT EXISTS resolution_note varchar(1000);
ALTER TABLE content_reports ADD COLUMN IF NOT EXISTS resolved_by uuid;
ALTER TABLE content_reports ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

ALTER TABLE content_reports ADD COLUMN IF NOT EXISTS submitted_at timestamptz;
UPDATE content_reports SET submitted_at = updated_at WHERE submitted_at IS NULL;
ALTER TABLE content_reports ALTER COLUMN submitted_at SET DEFAULT now();
ALTER TABLE content_reports ALTER COLUMN submitted_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_content_reports_reporter_submitted
  ON content_reports (reporter_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_reports_target
  ON content_reports (target_type, target_id);

CREATE TABLE IF NOT EXISTS content_report_actions (
  id                   uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id            uuid          NOT NULL REFERENCES content_reports(id) ON DELETE CASCADE,
  actor_id             uuid          REFERENCES users(id) ON DELETE SET NULL,
  -- Ảnh chụp lúc thao tác: dòng lịch sử giữ nguyên dù tài khoản admin về sau đổi email.
  actor_email          text          NOT NULL,
  action               varchar(30)   NOT NULL,
  from_status          varchar(20),
  to_status            varchar(20),
  -- Giá trị kết luận TRƯỚC thao tác, để hoàn tác trả về đúng như cũ.
  previous_note        varchar(1000),
  previous_resolved_by uuid,
  previous_resolved_at timestamptz,
  note                 varchar(1000) NOT NULL,
  sanctioned_user_id   uuid          REFERENCES users(id) ON DELETE SET NULL,
  reverts_action_id    uuid          REFERENCES content_report_actions(id) ON DELETE SET NULL,
  reverted_at          timestamptz,
  created_at           timestamptz   NOT NULL DEFAULT now(),

  CONSTRAINT ck_content_report_actions_action
    CHECK (action IN ('STATUS_CHANGED', 'USER_SUSPENDED', 'ROLLED_BACK')),
  CONSTRAINT ck_content_report_actions_status
    CHECK ((from_status IS NULL OR from_status IN ('PENDING', 'RESOLVED', 'REJECTED'))
       AND (to_status IS NULL OR to_status IN ('PENDING', 'RESOLVED', 'REJECTED')))
);

CREATE INDEX IF NOT EXISTS idx_content_report_actions_report
  ON content_report_actions (report_id, created_at DESC);

COMMIT;
