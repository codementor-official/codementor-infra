-- 0031 — index theo thời gian cho `submissions`.
--
-- Trang Chấm bài của admin lọc toàn bảng theo `submitted_at` (7 hoặc 30 ngày gần nhất). Hai
-- index hiện có đều bắt đầu bằng exercise_id / user_id nên không dùng được cho lọc đó, và
-- bảng này lớn dần theo mỗi lượt nộp.
--
-- Không phụ thuộc thứ tự deploy: chạy trước hay sau submission-service mới đều được.

BEGIN;

CREATE INDEX IF NOT EXISTS idx_submissions_submitted_at ON submissions (submitted_at DESC);

COMMIT;
