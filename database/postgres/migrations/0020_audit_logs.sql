-- 0020 — audit trail for administrative actions.
--
-- Owned by core-service, alongside `users`. Every action recorded here today is one that
-- core-service itself performs (role change, suspend, account creation), so the writer and
-- the owner are the same service and no cross-service write is needed. When article or
-- course moderation needs auditing too, those services should publish an event and an
-- audit consumer should write the row — not reach into this table directly.

BEGIN;

CREATE TABLE audit_logs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Ai làm. `ON DELETE SET NULL` chứ không CASCADE: xoá tài khoản quản trị không được
  -- xoá mất bằng chứng về những gì họ đã làm — đó là lúc cần bằng chứng nhất.
  actor_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  -- Chụp lại tại thời điểm ghi. `actor_id` có thể thành NULL, và một dòng nhật ký không
  -- nói được ai làm thì không còn là nhật ký kiểm toán.
  actor_email text NOT NULL,

  -- Động từ nghiệp vụ ở thì quá khứ, chấm phân cấp: `user.role_changed`, `user.suspended`.
  -- Không dùng enum: thêm một loại hành động không đáng phải migrate cả bảng.
  action      text NOT NULL,

  -- Đối tượng bị tác động. `target_id` để text chứ không uuid vì không phải đối tượng nào
  -- cũng khoá bằng uuid, và ràng buộc khoá ngoại ở đây sẽ chặn việc ghi nhật ký cho một
  -- bản ghi vừa bị xoá — đúng thứ cần ghi lại nhất.
  target_type text NOT NULL,
  target_id   text NOT NULL,

  -- Câu người đọc được, dựng lúc ghi. Dựng lúc đọc sẽ cần tra lại trạng thái cũ của mọi
  -- thứ liên quan, mà trạng thái ấy đã đổi rồi.
  summary     text NOT NULL,
  -- Chi tiết máy đọc được: giá trị trước/sau, lý do. Cho phép lọc mà không cần thêm cột.
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT audit_logs_action_not_blank  CHECK (btrim(action) <> ''),
  CONSTRAINT audit_logs_summary_not_blank CHECK (btrim(summary) <> '')
);

COMMENT ON TABLE audit_logs IS 'Append-only. Rows are never updated or deleted; a correction is a new row.';

-- Đường đọc chính là "mọi việc đã làm với đối tượng này", dùng cho drawer chi tiết tài khoản.
CREATE INDEX idx_audit_logs_target ON audit_logs (target_type, target_id, created_at DESC);
-- Đường đọc thứ hai là trang nhật ký chung, luôn sắp theo thời gian giảm dần.
CREATE INDEX idx_audit_logs_recent ON audit_logs (created_at DESC);

COMMIT;
