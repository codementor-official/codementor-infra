-- 0029 — phân nhóm từ vựng chủ đề dùng chung.
--
-- `tags` vẫn là chủ đề chi tiết gắn vào nội dung. `category` chỉ cung cấp tầng điều
-- hướng lớn cho catalogue (Thuật toán, Web, CSDL...), tránh tạo thêm một taxonomy
-- song song rồi phải đồng bộ khóa học/lộ trình/bài tập bằng tay.

BEGIN;

ALTER TABLE tags
  ADD COLUMN category text NOT NULL DEFAULT 'other';

ALTER TABLE tags
  ADD CONSTRAINT tags_category_check CHECK (
    category IN ('algorithms', 'database', 'web', 'systems', 'data_ai', 'foundations', 'other')
  );

CREATE INDEX idx_tags_category ON tags (category, name);

UPDATE tags SET category = CASE
  WHEN slug::text IN (
    'mang', 'chuoi', 'danh-sach-lien-ket', 'cay', 'do-thi', 'heap', 'hang-doi',
    'ngan-xep', 'hai-con-tro', 'sap-xep', 'tim-kiem-nhi-phan', 'quay-lui',
    'quy-hoach-dong', 'de-quy', 'vong-lap'
  ) THEN 'algorithms'
  WHEN slug::text IN ('co-so-du-lieu', 'sql', 'postgresql', 'mysql') THEN 'database'
  WHEN slug::text IN ('front-end', 'javascript', 'react', 'tailwind-css', 'websocket', 'css', 'html') THEN 'web'
  WHEN slug::text IN ('back-end', 'devops', 'shell', 'concurrency', 'docker', 'networking') THEN 'systems'
  WHEN slug::text IN ('python', 'pandas', 'machine-learning', 'data-ai') THEN 'data_ai'
  WHEN slug::text IN ('nhap-mon', 'lo-trinh-hoc', 'cong-cu', 'kiem-thu') THEN 'foundations'
  ELSE 'other'
END;

COMMIT;
