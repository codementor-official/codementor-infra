-- 0024 — chủ đề cho khóa học và lộ trình.
--
-- `exercise_tags` đã có, `course`/`roadmap` thì không: hai loại nội dung lớn nhất trong
-- catalog không nói được chúng dạy về cái gì, ngoài `field` (sáu giá trị) và `level`.
-- Hệ đề xuất vì thế chỉ khớp được bài tập theo chủ đề, còn khóa học và lộ trình thì không.
--
-- Cùng khuôn với `exercise_tags`: bảng nối, khóa chính kép, `ON DELETE RESTRICT` phía tag
-- để không ai xoá mất một chủ đề đang được dùng.

BEGIN;

CREATE TABLE course_tags (
  course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  tag_id    uuid NOT NULL REFERENCES tags(id)    ON DELETE RESTRICT,
  PRIMARY KEY (course_id, tag_id)
);

CREATE INDEX idx_course_tags_tag ON course_tags (tag_id);

CREATE TABLE roadmap_tags (
  roadmap_id uuid NOT NULL REFERENCES roadmaps(id) ON DELETE CASCADE,
  tag_id     uuid NOT NULL REFERENCES tags(id)     ON DELETE RESTRICT,
  PRIMARY KEY (roadmap_id, tag_id)
);

CREATE INDEX idx_roadmap_tags_tag ON roadmap_tags (tag_id);

COMMENT ON TABLE course_tags IS
  'Chủ đề do tác giả gắn cho khóa học. Hệ đề xuất còn gom thêm chủ đề của bài tập nằm trong khóa, nhưng phần gom đó tính lúc đọc chứ không lưu ở đây.';
COMMENT ON TABLE roadmap_tags IS
  'Chủ đề do tác giả gắn cho lộ trình. Chủ đề của các khóa bên trong được gom thêm lúc đọc.';

COMMIT;
