-- Seed data. Deterministic UUIDs so the set can be re-created and referenced from docs/tests.
--
-- Demonstrates every shape the brief asks for:
--   LINEAR          roadmap "Nhập môn Lập trình" (progression_mode='linear', zero edges)
--   BRANCHING       Java Core chapter 1: L1 → {L2, L3, L4}
--   UNCONSTRAINED   roadmap "Frontend Developer" (progression_mode='free', zero edges)
--   MULTIPLE (AND)  Spring Boot REST API requires Java Core AND SQL cơ bản
--                   lesson "Class và Object" requires "Kiểu dữ liệu" AND "Toán tử"
--   ALTERNATIVE(OR) exercise "Rate limiter" requires "JWT guard" OR "API pagination"
--   MODE OVERRIDE   learner `an` opts out of gating on the algorithms track

BEGIN;

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------
INSERT INTO users (id, email, handle, display_name, bio, role, email_verified_at, last_active_at) VALUES
  ('a0000000-0000-4000-8000-000000000001', 'giasi@codementor.vn', 'giasi',   'Nguyễn Trần Gia Sĩ', 'Đang xây nền tảng Backend Java.', 'learner', now(), now()),
  ('a0000000-0000-4000-8000-000000000002', 'minhanh@codementor.vn','minhanh','Nguyễn Minh Anh',    'Mentor Frontend & Thuật toán.',   'mentor',  now(), now()),
  ('a0000000-0000-4000-8000-000000000003', 'an@codementor.vn',     'anlearner','Trần Hoài An',     'Thích tự chọn bài để luyện.',     'learner', now(), now()),
  ('a0000000-0000-4000-8000-000000000004', 'admin@codementor.vn',  'admin',   'Quản trị hệ thống',  NULL,                              'admin',   now(), now());

INSERT INTO user_stats (user_id, xp, solved_count, current_streak_days, longest_streak_days, last_solved_on) VALUES
  ('a0000000-0000-4000-8000-000000000001', 2450, 47, 5, 12, current_date),
  ('a0000000-0000-4000-8000-000000000003',  980, 21, 2,  9, current_date - 1);

INSERT INTO learning_preferences
  (user_id, learning_goal, career_goal, current_level, content_priority, weekly_study_hours,
   interested_fields, preferred_learning_styles, reminders_enabled, reminder_time, completed_at)
VALUES
  ('a0000000-0000-4000-8000-000000000001', 'Học để đi làm', 'Backend Developer', 'basic', 'practice', 5,
   '{backend,foundation}', '{video,practice}', true, '18:45', now()),
  ('a0000000-0000-4000-8000-000000000003', 'Chuẩn bị phỏng vấn', 'Web Developer', 'intermediate', 'practice', 8,
   '{frontend,fullstack}', '{practice,project}', false, NULL, now());

INSERT INTO study_schedule_slots (user_id, weekday, enabled, start_time, duration_minutes)
SELECT 'a0000000-0000-4000-8000-000000000001', d, d IN ('mon','tue','wed','thu','fri'), '19:00', 60
FROM unnest(enum_range(NULL::weekday)) AS d;

-- ---------------------------------------------------------------------------
-- Taxonomy
-- ---------------------------------------------------------------------------
INSERT INTO technologies (slug, name) VALUES
  ('java','Java'), ('spring-boot','Spring Boot'), ('sql','SQL'), ('html','HTML'),
  ('css','CSS'), ('javascript','JavaScript'), ('react','React'), ('typescript','TypeScript'),
  ('python','Python'), ('cpp','C++'), ('nodejs','Node.js'), ('c','C');

-- Two vocabularies in one table, on purpose: the first row covers what an *exercise* is
-- about, the second what an *article* is about. Splitting them into two tables would
-- duplicate every join and every filter for no gain — a tag is a tag.
--
-- ON CONFLICT so this block can be re-run on its own against a live database when new
-- topics are added, without replaying the rest of the seed.
INSERT INTO tags (slug, name) VALUES
  ('mang','Mảng'), ('thuat-toan','Thuật toán'), ('oop','OOP'), ('dom','DOM'),
  ('rest-api','REST API'), ('security','Security'), ('sap-xep','Sắp xếp'), ('tim-kiem','Tìm kiếm'),
  ('front-end','Front-end'), ('back-end','Back-end'), ('javascript','JavaScript'),
  ('react','React'), ('tailwind-css','Tailwind CSS'), ('websocket','WebSocket'),
  ('co-so-du-lieu','Cơ sở dữ liệu'), ('kiem-thu','Kiểm thử'), ('devops','DevOps'),
  ('cong-cu','Công cụ'), ('lo-trinh-hoc','Lộ trình học'), ('kinh-nghiem','Kinh nghiệm')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO companies (slug, name) VALUES
  ('vng','VNG'), ('momo','MoMo'), ('viettel','Viettel'), ('fpt-software','FPT Software');

-- ---------------------------------------------------------------------------
-- Courses
-- ---------------------------------------------------------------------------
INSERT INTO courses (id, slug, title, description, level, duration_hours, instructor_id,
                     progression_mode, status, published_at, created_by) VALUES
  ('c0000000-0000-4000-8000-000000000001','java-core','Java Core','Cú pháp Java, OOP cơ bản và Collections Framework.','basic',26,
   'a0000000-0000-4000-8000-000000000002','graph','published', now(),'a0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-000000000002','sql-co-ban','SQL cơ bản','Truy vấn, JOIN và thiết kế bảng quan hệ.','basic',18,
   'a0000000-0000-4000-8000-000000000002','graph','published', now(),'a0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-000000000003','spring-boot-rest-api','Spring Boot REST API','Xây dựng REST API với Spring Boot và JPA.','intermediate',28,
   'a0000000-0000-4000-8000-000000000002','graph','published', now(),'a0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-000000000004','du-an-backend','Dự án Backend tổng hợp','Ghép mọi thứ thành một hệ thống có xác thực.','intermediate',20,
   'a0000000-0000-4000-8000-000000000002','graph','published', now(),'a0000000-0000-4000-8000-000000000002'),
  -- Frontend roadmap courses (unconstrained)
  ('c0000000-0000-4000-8000-000000000005','html-co-ban','HTML cơ bản','Cấu trúc trang web và thẻ ngữ nghĩa.','none',10,
   'a0000000-0000-4000-8000-000000000002','free','published', now(),'a0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-000000000006','css-co-ban','CSS cơ bản','Box model, Flexbox và Grid.','none',14,
   'a0000000-0000-4000-8000-000000000002','free','published', now(),'a0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-000000000007','javascript-co-ban','JavaScript cơ bản','Biến, hàm, DOM và xử lý sự kiện.','basic',22,
   'a0000000-0000-4000-8000-000000000002','free','published', now(),'a0000000-0000-4000-8000-000000000002'),
  -- Foundation roadmap courses (linear)
  ('c0000000-0000-4000-8000-000000000008','tu-duy-lap-trinh','Tư duy lập trình','Thuật toán, lưu đồ và phân rã bài toán.','none',8,
   'a0000000-0000-4000-8000-000000000002','linear','published', now(),'a0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-000000000009','lap-trinh-c','Lập trình C cơ bản','Biến, điều kiện và vòng lặp bằng C.','none',24,
   'a0000000-0000-4000-8000-000000000002','linear','published', now(),'a0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-00000000000a','cau-truc-du-lieu','Cấu trúc dữ liệu cơ bản','Mảng, danh sách liên kết, ngăn xếp.','basic',20,
   'a0000000-0000-4000-8000-000000000002','linear','published', now(),'a0000000-0000-4000-8000-000000000002');

INSERT INTO course_outcomes (course_id, position, text) VALUES
  ('c0000000-0000-4000-8000-000000000001',1,'Nắm vững OOP trong Java'),
  ('c0000000-0000-4000-8000-000000000001',2,'Sử dụng thành thạo Collections Framework'),
  ('c0000000-0000-4000-8000-000000000003',1,'Xây dựng REST API CRUD hoàn chỉnh'),
  ('c0000000-0000-4000-8000-000000000003',2,'Kết nối cơ sở dữ liệu bằng Spring Data JPA');

INSERT INTO course_technologies (course_id, technology_id)
SELECT c.id, t.id FROM courses c JOIN technologies t ON true
WHERE (c.slug, t.slug) IN (
  ('java-core','java'), ('sql-co-ban','sql'),
  ('spring-boot-rest-api','java'), ('spring-boot-rest-api','spring-boot'),
  ('html-co-ban','html'), ('css-co-ban','css'), ('javascript-co-ban','javascript'),
  ('lap-trinh-c','c'), ('cau-truc-du-lieu','c')
);

-- === MULTIPLE PREREQUISITES (AND) ==========================================
-- Spring Boot REST API requires Java Core AND SQL cơ bản — both in group 0.
INSERT INTO course_prerequisites (target_course_id, source_course_id, group_index) VALUES
  ('c0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000001',0),
  ('c0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000002',0);

-- ---------------------------------------------------------------------------
-- Roadmaps
-- ---------------------------------------------------------------------------
INSERT INTO roadmaps (id, slug, title, short_description, description, field, level,
                      estimated_hours, progression_mode, status, popularity_score, published_at) VALUES
  ('b0000000-0000-4000-8000-000000000001','backend-java','Lộ trình Backend Java',
   'Xây dựng API và hệ thống backend vững chắc với Java & Spring Boot.',
   'Đi từ Java Core đến REST API hoàn chỉnh.','backend','intermediate',120,'graph','published',74, now()),
  ('b0000000-0000-4000-8000-000000000002','frontend-developer','Lộ trình Frontend Developer',
   'Từ HTML/CSS đến React.','Học theo thứ tự bạn muốn — không khoá bài.','frontend','basic',140,'free','published',88, now()),
  ('b0000000-0000-4000-8000-000000000003','nhap-mon','Lộ trình Nhập môn Lập trình',
   'Xuất phát điểm cho người chưa từng viết code.','Đi tuần tự từng bước một.','foundation','none',96,'linear','published',92, now());

INSERT INTO roadmap_outcomes (roadmap_id, position, text) VALUES
  ('b0000000-0000-4000-8000-000000000001',1,'Xây dựng REST API CRUD hoàn chỉnh với Spring Boot'),
  ('b0000000-0000-4000-8000-000000000001',2,'Thiết kế cơ sở dữ liệu quan hệ và dùng JPA hiệu quả');

INSERT INTO roadmap_audiences (roadmap_id, position, text) VALUES
  ('b0000000-0000-4000-8000-000000000001',1,'Người muốn trở thành Backend Developer');

-- Membership rows. `position` is DISPLAY ORDER only.
INSERT INTO roadmap_courses (id, roadmap_id, course_id, position) VALUES
  -- Backend Java (graph — explicit edges below)
  ('d0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001',1),
  ('d0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002',2),
  ('d0000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000003',3),
  ('d0000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000004',4),
  -- === UNCONSTRAINED: no edges at all, mode='free' ===
  ('d0000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000005',1),
  ('d0000000-0000-4000-8000-000000000006','b0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000006',2),
  ('d0000000-0000-4000-8000-000000000007','b0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000007',3),
  -- === LINEAR: no edges either — ordering IS the gate when mode='linear' ===
  ('d0000000-0000-4000-8000-000000000008','b0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000008',1),
  ('d0000000-0000-4000-8000-000000000009','b0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000009',2),
  ('d0000000-0000-4000-8000-00000000000a','b0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-00000000000a',3);

-- === BRANCHING + AND JOIN at roadmap level =================================
--   Java Core ──┬──▶ SQL cơ bản ──┐
--               └──────────────────┴─(group 0: AND)──▶ Spring Boot ──▶ Dự án
INSERT INTO roadmap_course_prerequisites
  (roadmap_id, target_roadmap_course_id, source_roadmap_course_id, group_index) VALUES
  ('b0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001',0),
  ('b0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001',0),
  ('b0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000002',0),
  ('b0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000004','d0000000-0000-4000-8000-000000000003',0);

-- ---------------------------------------------------------------------------
-- Java Core curriculum
-- ---------------------------------------------------------------------------
INSERT INTO chapters (id, course_id, title, description, position) VALUES
  ('e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Cú pháp và Kiểu dữ liệu','Biến, kiểu dữ liệu và toán tử.',1),
  ('e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','Lập trình hướng đối tượng','Lớp, đối tượng, kế thừa.',2);

INSERT INTO lessons (id, chapter_id, course_id, title, type, duration_minutes, is_preview, position, content_ref) VALUES
  ('f0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Cú pháp Java cơ bản','video',14,true, 1,'65f00000000000000000ff01'),
  ('f0000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Kiểu dữ liệu nguyên thủy','article',10,false,2,'65f00000000000000000ff02'),
  ('f0000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Toán tử và biểu thức','video',12,false,3,'65f00000000000000000ff03'),
  ('f0000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Nhập xuất dữ liệu','article',9, false,4,'65f00000000000000000ff04'),
  ('f0000000-0000-4000-8000-000000000005','e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','Class và Object','video',16,false,1,'65f00000000000000000ff05'),
  ('f0000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','Kế thừa và đa hình','video',18,false,2,'65f00000000000000000ff06'),
  ('f0000000-0000-4000-8000-000000000007','e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','Bài tập: Quản lý thư viện','exercise',40,false,3,'65f00000000000000000ff07');

-- Chapter 2 needs chapter 1.
INSERT INTO chapter_prerequisites (course_id, target_chapter_id, source_chapter_id, group_index) VALUES
  ('c0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001',0);

-- === BRANCHING at lesson level =============================================
--   L1 ──┬──▶ L2
--        ├──▶ L3
--        └──▶ L4          L2/L3/L4 independent, any order, after L1
-- === plus an AND JOIN, cross-chapter ========================================
--   L2 ──┐
--        ├─(group 0: AND)──▶ L5 "Class và Object"
--   L3 ──┘
INSERT INTO lesson_prerequisites (course_id, target_lesson_id, source_lesson_id, group_index) VALUES
  ('c0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000002','f0000000-0000-4000-8000-000000000001',0),
  ('c0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000003','f0000000-0000-4000-8000-000000000001',0),
  ('c0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000004','f0000000-0000-4000-8000-000000000001',0),
  ('c0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000005','f0000000-0000-4000-8000-000000000002',0),
  ('c0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000005','f0000000-0000-4000-8000-000000000003',0),
  ('c0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000006','f0000000-0000-4000-8000-000000000005',0),
  ('c0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000007','f0000000-0000-4000-8000-000000000006',0);

-- Frontend + foundation courses get one chapter each so progress maths has something to bite on.
INSERT INTO chapters (id, course_id, title, position) VALUES
  ('e0000000-0000-4000-8000-000000000005','c0000000-0000-4000-8000-000000000005','Cấu trúc tài liệu HTML',1),
  ('e0000000-0000-4000-8000-000000000008','c0000000-0000-4000-8000-000000000008','Thuật toán là gì',1);

INSERT INTO lessons (id, chapter_id, course_id, title, type, duration_minutes, position, content_ref) VALUES
  ('f0000000-0000-4000-8000-000000000010','e0000000-0000-4000-8000-000000000005','c0000000-0000-4000-8000-000000000005','Thẻ HTML cơ bản','video',10,1,'65f00000000000000000ff10'),
  ('f0000000-0000-4000-8000-000000000011','e0000000-0000-4000-8000-000000000005','c0000000-0000-4000-8000-000000000005','Thẻ ngữ nghĩa','article',8,2,'65f00000000000000000ff11'),
  ('f0000000-0000-4000-8000-000000000012','e0000000-0000-4000-8000-000000000008','c0000000-0000-4000-8000-000000000008','Giới thiệu tư duy thuật toán','video',10,1,'65f00000000000000000ff12'),
  ('f0000000-0000-4000-8000-000000000013','e0000000-0000-4000-8000-000000000008','c0000000-0000-4000-8000-000000000008','Quiz: Nhận diện bài toán','quiz',8,2,'65f00000000000000000ff13');

-- ---------------------------------------------------------------------------
-- Exercises
-- ---------------------------------------------------------------------------
INSERT INTO exercises (id, slug, title, summary, kind, difficulty, status, xp_reward,
                       estimated_minutes, author_id, content_ref, published_at) VALUES
  ('10000000-0000-4000-8000-000000000001','tim-kiem-tuyen-tinh','Tìm kiếm tuyến tính','Duyệt mảng tìm phần tử.','code','easy','published',25,20,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee01', now()),
  ('10000000-0000-4000-8000-000000000002','tim-kiem-nhi-phan','Tìm kiếm nhị phân','Tìm nhanh trên mảng đã sắp xếp.','code','medium','published',50,30,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee02', now()),
  ('10000000-0000-4000-8000-000000000003','sap-xep-noi-bot','Sắp xếp nổi bọt','Cài đặt bubble sort.','code','easy','published',25,25,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee03', now()),
  ('10000000-0000-4000-8000-000000000004','sap-xep-tron','Sắp xếp trộn','Cài đặt merge sort.','code','hard','published',80,45,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee04', now()),
  ('10000000-0000-4000-8000-000000000005','tim-nghiem-chia-doi','Tìm nghiệm bằng chia đôi','Áp dụng nhị phân trên miền thực.','code','hard','published',80,40,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee05', now()),
  ('10000000-0000-4000-8000-000000000006','jwt-route-guard','Bảo vệ API bằng JWT','Kiểm tra token và phân quyền.','code','hard','published',80,60,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee06', now()),
  ('10000000-0000-4000-8000-000000000007','api-pagination','Phân trang API','Trả về danh sách theo trang.','code','medium','published',50,45,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee07', now()),
  ('10000000-0000-4000-8000-000000000008','rate-limiter','Giới hạn số lần gọi API','Bộ đếm cửa sổ thời gian.','code','hard','published',80,60,
   'a0000000-0000-4000-8000-000000000002','65f00000000000000000ee08', now());

-- The exercise lesson in Java Core actually runs an exercise now (frontend had no such link).
UPDATE lessons SET exercise_id = '10000000-0000-4000-8000-000000000001'
WHERE id = 'f0000000-0000-4000-8000-000000000007';

INSERT INTO exercise_tags (exercise_id, tag_id)
SELECT e.id, t.id FROM exercises e JOIN tags t ON true
WHERE (e.slug, t.slug) IN (
  ('tim-kiem-tuyen-tinh','tim-kiem'), ('tim-kiem-nhi-phan','tim-kiem'),
  ('sap-xep-noi-bot','sap-xep'), ('sap-xep-tron','sap-xep'),
  ('jwt-route-guard','security'), ('api-pagination','rest-api'), ('rate-limiter','rest-api')
);

INSERT INTO exercise_companies (exercise_id, company_id)
SELECT e.id, c.id FROM exercises e JOIN companies c ON true
WHERE (e.slug, c.slug) IN (('tim-kiem-nhi-phan','vng'), ('rate-limiter','momo'), ('sap-xep-tron','viettel'));

-- ---------------------------------------------------------------------------
-- Exercise sets — the SAME exercises under different progression rules,
-- which is the point: no duplication.
-- ---------------------------------------------------------------------------
INSERT INTO exercise_sets (id, slug, title, description, kind, progression_mode, status) VALUES
  ('20000000-0000-4000-8000-000000000001','nhap-mon-thuat-toan','Nhập môn thuật toán','Đi theo thứ tự có khoá.','track','graph','published'),
  ('20000000-0000-4000-8000-000000000002','top-100-phong-van','Top 100 phỏng vấn','Chọn bài tự do.','collection','free','published'),
  ('20000000-0000-4000-8000-000000000003','backend-nang-cao','Backend nâng cao','Có nhánh thay thế.','track','graph','published');

INSERT INTO exercise_set_items (set_id, exercise_id, position) VALUES
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',1),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',2),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003',3),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004',4),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000005',5),
  -- same five exercises, zero edges → unconstrained
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001',1),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002',2),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003',3),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004',4),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000005',5),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000006',6),
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000006',1),
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000007',2),
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000008',3);

-- === BRANCHING exercise graph ==============================================
--   E1 ──┬──▶ E2 ──▶ E5
--        └──▶ E3 ──▶ E4
INSERT INTO exercise_prerequisites (set_id, target_exercise_id, source_exercise_id, group_index) VALUES
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001',0),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001',0),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000002',0),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000003',0);

-- === ALTERNATIVE PREREQUISITES (OR) ========================================
-- Rate limiter opens after EITHER the JWT guard (group 0) OR API pagination (group 1).
INSERT INTO exercise_prerequisites (set_id, target_exercise_id, source_exercise_id, group_index) VALUES
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000006',0),
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000007',1);

-- === LEARNER MODE OVERRIDE =================================================
-- `an` opts out of gating on the algorithms track; `giasi` keeps it enforced.
INSERT INTO exercise_set_enrollments (user_id, set_id, progression_mode_override) VALUES
  ('a0000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','free'),
  ('a0000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001', NULL);

-- ---------------------------------------------------------------------------
-- Enrolment + progress. The caches below are written by triggers, not by these INSERTs.
-- ---------------------------------------------------------------------------
INSERT INTO roadmap_enrollments (user_id, roadmap_id) VALUES
  ('a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001');

INSERT INTO course_enrollments (user_id, course_id, via_roadmap_id) VALUES
  ('a0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001');

-- giasi finished L1, L2, L3 → L4 and L5 become available (L5 needed BOTH L2 and L3).
INSERT INTO lesson_progress (user_id, lesson_id, status, started_at, completed_at, time_spent_seconds) VALUES
  ('a0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000001','completed', now()-interval '3 day', now()-interval '3 day', 900),
  ('a0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000002','completed', now()-interval '2 day', now()-interval '2 day', 640),
  ('a0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000003','completed', now()-interval '1 day', now()-interval '1 day', 700);

INSERT INTO exercise_progress (user_id, exercise_id, status, best_score, attempt_count, is_favorite, first_solved_at, last_attempt_at) VALUES
  ('a0000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','solved', 100, 2, true,  now()-interval '2 day', now()-interval '2 day'),
  ('a0000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','attempted', 60, 1, false, NULL, now()-interval '1 day'),
  ('a0000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','solved', 100, 1, false, now()-interval '5 day', now()-interval '5 day');

-- ---------------------------------------------------------------------------
-- Study group
-- ---------------------------------------------------------------------------
INSERT INTO study_groups (id, slug, name, description, invite_code, topic, owner_id, last_activity_at) VALUES
  ('30000000-0000-4000-8000-000000000001','nhom-java-k18','Nhóm Java K18','Cùng nhau qua môn Java.','JAVA18','Java',
   'a0000000-0000-4000-8000-000000000001', now());

INSERT INTO group_members (id, group_id, user_id, role) VALUES
  ('31000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','owner'),
  ('31000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','member'),
  ('31000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','deputy');

-- Role defaults, then a per-person override: this deputy may not remove members.
INSERT INTO group_role_permissions (group_id, role, permission, allowed) VALUES
  ('30000000-0000-4000-8000-000000000001','deputy','upload_doc',true),
  ('30000000-0000-4000-8000-000000000001','deputy','create_exercise',true),
  ('30000000-0000-4000-8000-000000000001','deputy','edit_exercise',true),
  ('30000000-0000-4000-8000-000000000001','deputy','delete_doc',false),
  ('30000000-0000-4000-8000-000000000001','deputy','review_submission',true),
  ('30000000-0000-4000-8000-000000000001','deputy','remove_member',true),
  ('30000000-0000-4000-8000-000000000001','member','upload_doc',true),
  ('30000000-0000-4000-8000-000000000001','member','create_exercise',false),
  ('30000000-0000-4000-8000-000000000001','member','edit_exercise',false),
  ('30000000-0000-4000-8000-000000000001','member','delete_doc',false),
  ('30000000-0000-4000-8000-000000000001','member','review_submission',false),
  ('30000000-0000-4000-8000-000000000001','member','remove_member',false);

INSERT INTO group_member_permissions (group_member_id, permission, allowed) VALUES
  ('31000000-0000-4000-8000-000000000003','remove_member', false);

INSERT INTO group_documents (id, group_id, title, doc_type, topic, uploader_id, size_bytes, storage_key, status, ai_verdict) VALUES
  ('32000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','Slide OOP buổi 3','Slide','Java',
   'a0000000-0000-4000-8000-000000000001', 2516582, 'groups/nhom-java-k18/slide-oop-3.pdf','published','valid');

INSERT INTO group_exercises (id, group_id, exercise_id, assigned_by, due_at, attempt_limit, allow_late_submission, phase) VALUES
  ('33000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',
   'a0000000-0000-4000-8000-000000000001', now() + interval '7 day', 3, true, 'Tuần 3');

INSERT INTO assignments (id, group_id, group_exercise_id, member_id, status, review_status, started_at) VALUES
  ('34000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001',
   '31000000-0000-4000-8000-000000000002','inprogress','pending', now() - interval '1 day');

-- A group submission (has assignment_id) and a free-practice one (does not).
INSERT INTO submissions (user_id, exercise_id, assignment_id, language, source_code, verdict,
                         score, passed_tests, total_tests, runtime_ms, memory_kb, attempt_number) VALUES
  ('a0000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','34000000-0000-4000-8000-000000000001',
   'python','def solve(): pass','wrong_answer', 60, 3, 5, 42, 15360, 1),
  ('a0000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001', NULL,
   'python','print(sum(1))','accepted', 100, 4, 4, 18, 14080, 2);

INSERT INTO group_activities (group_id, actor_id, action, target_type, target_id) VALUES
  ('30000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','submitted','assignment','34000000-0000-4000-8000-000000000001');

-- ---------------------------------------------------------------------------
-- Reviews + articles
-- ---------------------------------------------------------------------------
INSERT INTO course_reviews (course_id, user_id, rating, comment) VALUES
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',5,'Giải thích dễ hiểu.'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003',4,'Cần thêm bài tập.');

INSERT INTO articles (id, slug, title, excerpt, takeaway, author_id, tag_id, read_minutes, status, content_ref, published_at)
VALUES ('40000000-0000-4000-8000-000000000001','hieu-big-o-trong-10-phut','Hiểu Big-O trong 10 phút',
        'Ước lượng độ phức tạp bằng trực giác.','Đếm số lần lặp khi dữ liệu tăng.',
        'a0000000-0000-4000-8000-000000000002',(SELECT id FROM tags WHERE slug='thuat-toan'),8,'published','65f00000000000000000aa01', now());

COMMIT;
