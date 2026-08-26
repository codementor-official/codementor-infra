-- Chủ đề cho bài tập.
--
-- `tags` trước đây chỉ phục vụ bài viết ("Kinh nghiệm", "Lộ trình học") và `exercise_tags`
-- rỗng hoàn toàn, nên không có tín hiệu chủ đề nào cho hệ đề xuất: một bài về đệ quy và
-- một bài về đồ thị chỉ khác nhau ở tiêu đề. Đây là từ vựng chủ đề đầu tiên, cộng với việc
-- gắn cho các bài demo đã xuất bản.
--
-- Chạy lại được: mọi câu đều ON CONFLICT DO NOTHING, không câu nào xoá gì.

BEGIN;

INSERT INTO tags (slug, name) VALUES
  ('mang',              'Mảng'),
  ('chuoi',             'Chuỗi'),
  ('danh-sach-lien-ket','Danh sách liên kết'),
  ('ngan-xep',          'Ngăn xếp'),
  ('hang-doi',          'Hàng đợi'),
  ('heap',              'Heap'),
  ('cay',               'Cây'),
  ('do-thi',            'Đồ thị'),
  ('sap-xep',           'Sắp xếp'),
  ('tim-kiem-nhi-phan', 'Tìm kiếm nhị phân'),
  ('hai-con-tro',       'Hai con trỏ'),
  ('de-quy',            'Đệ quy'),
  ('vong-lap',          'Vòng lặp'),
  ('nhap-mon',          'Nhập môn')
ON CONFLICT (slug) DO NOTHING;

-- Gắn theo slug bài tập, không theo id: bài do giảng viên soạn có id ngẫu nhiên, và slug
-- là thứ duy nhất ổn định giữa các môi trường.
INSERT INTO exercise_tags (exercise_id, tag_id)
SELECT e.id, t.id
FROM (VALUES
  ('demo-dsa-array-two-pointers',          ARRAY['mang', 'hai-con-tro']),
  ('demo-dsa-reverse-linked-list',         ARRAY['danh-sach-lien-ket']),
  ('demo-linked-list-workspace',           ARRAY['danh-sach-lien-ket']),
  ('demo-dsa-valid-parentheses-stack',     ARRAY['ngan-xep', 'chuoi']),
  ('demo-dsa-priority-queue-simulation',   ARRAY['hang-doi', 'heap']),
  ('demo-dsa-binary-search',               ARRAY['tim-kiem-nhi-phan', 'mang']),
  ('demo-binary-search-workspace',         ARRAY['tim-kiem-nhi-phan', 'mang']),
  ('demo-dsa-binary-tree-height',          ARRAY['cay', 'de-quy']),
  ('demo-dsa-validate-binary-search-tree', ARRAY['cay', 'de-quy']),
  ('demo-dsa-top-k-elements-heap',         ARRAY['heap', 'mang']),
  ('demo-dsa-bfs-shortest-path',           ARRAY['do-thi']),
  ('demo-dsa-dfs-connected-components',    ARRAY['do-thi', 'de-quy']),
  ('demo-dsa-dijkstra-shortest-path',      ARRAY['do-thi', 'heap']),
  ('demo-dsa-topological-sort-kahn',       ARRAY['do-thi', 'sap-xep']),
  ('sap-xep-mang',                         ARRAY['sap-xep', 'mang']),
  ('tim-so-lon-nhat',                      ARRAY['mang', 'vong-lap']),
  ('bai-tap-chua-dat-ten-eufsx',           ARRAY['mang', 'vong-lap']),
  ('min-num',                              ARRAY['mang', 'vong-lap']),
  ('py-dem-so-chan',                       ARRAY['mang', 'vong-lap']),
  ('py-dao-nguoc-chuoi',                   ARRAY['chuoi']),
  ('py-tong-hai-so',                       ARRAY['nhap-mon']),
  ('bai-tap-chua-dat-ten-br78r',           ARRAY['front-end'])
) AS seed(slug, tag_slugs)
JOIN exercises e ON e.slug = seed.slug::citext
JOIN tags t ON t.slug = ANY (seed.tag_slugs::citext[])
ON CONFLICT DO NOTHING;

COMMIT;
