-- 0019 — bài viết đi qua kiểm duyệt như khoá học và lộ trình.
--
-- Additive only. Không đổi tên, không xoá cột, không đụng tới hàng nào đang có.
--
-- `articles.status` vốn đã là `content_status`, và migration 0018 đã thêm
-- `pending_review` / `changes_requested` / `rejected` vào enum đó — nên bài viết dùng
-- được ngay máy trạng thái ấy mà không cần đổi kiểu.
--
-- Thứ duy nhất còn thiếu là chỗ ghi LÝ DO khi admin từ chối hoặc yêu cầu sửa. `courses`,
-- `roadmaps` và `exercises` đều đã có cột này; không có nó thì người viết chỉ thấy bài
-- mình bị trả lại mà không biết vì sao, và cả quy trình duyệt trở thành vô nghĩa.

BEGIN;

ALTER TABLE articles ADD COLUMN IF NOT EXISTS rejection_reason text;

COMMENT ON COLUMN articles.rejection_reason IS
  'Lý do admin từ chối hoặc yêu cầu sửa. NULL khi bài chưa từng bị trả lại, và được xoá về NULL mỗi lần bài được duyệt.';

COMMIT;
