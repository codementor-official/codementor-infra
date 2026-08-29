BEGIN;

-- Nội dung người học lưu để xem lại. `target_id` là khoá ở service sở hữu nội dung,
-- vì một foreign key đa hình không thể trỏ đồng thời tới course/roadmap/exercise/article.
CREATE TABLE IF NOT EXISTS user_bookmarks (
  id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type varchar(20)  NOT NULL,
  target_id   uuid         NOT NULL,
  target_ref  varchar(240),
  created_at  timestamptz  NOT NULL DEFAULT now(),

  CONSTRAINT ck_user_bookmarks_target_type
    CHECK (target_type IN ('COURSE', 'ROADMAP', 'EXERCISE', 'POST')),
  CONSTRAINT uq_user_bookmarks_target UNIQUE (user_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_user_bookmarks_user_created
  ON user_bookmarks (user_id, created_at DESC);

-- Báo cáo moderation dùng chung. Giai đoạn client chỉ cần tiếp nhận và giữ PENDING;
-- admin workflow có thể mở rộng status/assignee sau mà không thay đổi API submit.
CREATE TABLE IF NOT EXISTS content_reports (
  id          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type varchar(20)   NOT NULL,
  target_id   uuid          NOT NULL,
  target_ref  varchar(240),
  category    varchar(30)   NOT NULL,
  note        varchar(1000),
  status      varchar(20)   NOT NULL DEFAULT 'PENDING',
  created_at  timestamptz   NOT NULL DEFAULT now(),
  updated_at  timestamptz   NOT NULL DEFAULT now(),

  CONSTRAINT ck_content_reports_target_type
    CHECK (target_type IN ('DOCUMENT', 'POST', 'COURSE', 'ROADMAP', 'EXERCISE', 'WORKSPACE')),
  CONSTRAINT ck_content_reports_category
    CHECK (category IN ('SPAM', 'MISLEADING', 'INAPPROPRIATE', 'COPYRIGHT', 'OTHER')),
  CONSTRAINT ck_content_reports_status
    CHECK (status IN ('PENDING', 'RESOLVED', 'REJECTED')),
  CONSTRAINT uq_content_reports_reporter_target
    UNIQUE (reporter_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_content_reports_status_created
  ON content_reports (status, created_at DESC);

COMMIT;
