-- 0015 — cắt phụ thuộc hai chiều giữa Exercise và Workspace.
--
-- Trước:
--   exercises.owner_group_id    → study_groups   (exercise phải biết group)
--   group_exercises.exercise_id → exercises      (group phải biết exercise)
--
-- Vòng phụ thuộc này khiến không thể cấp GRANT sạch cho hai service riêng biệt, và sẽ
-- vỡ hẳn khi tách database. Sau migration, phụ thuộc chỉ còn một chiều: workspace → exercise.
--
-- Câu hỏi "nhóm nào sở hữu bài tập này" từ nay do `group_exercises` trả lời — đó là bảng
-- của workspace-service, đúng nơi biết về nhóm.

BEGIN;

CREATE TYPE exercise_visibility AS ENUM ('public', 'group');

ALTER TABLE exercises
  ADD COLUMN visibility exercise_visibility NOT NULL DEFAULT 'public';

COMMENT ON COLUMN exercises.visibility IS
  'public = catalog chung; group = chỉ hiện trong nhóm đã publish qua group_exercises. Không tham chiếu trực tiếp tới study_groups.';

-- Giữ nguyên ngữ nghĩa dữ liệu đang có trước khi bỏ cột.
UPDATE exercises SET visibility = 'group' WHERE owner_group_id IS NOT NULL;

-- Bỏ index phụ thuộc cột sắp xoá, rồi xoá cột.
DROP INDEX IF EXISTS idx_exercises_group;
ALTER TABLE exercises DROP COLUMN owner_group_id;

-- Catalog chung là truy vấn nóng nhất của exercise-service.
CREATE INDEX idx_exercises_public_catalog
  ON exercises (difficulty, status)
  WHERE visibility = 'public' AND status = 'published';

COMMIT;
