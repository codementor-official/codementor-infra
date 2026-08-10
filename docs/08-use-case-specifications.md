# Đặc tả Use Case chi tiết

Đặc tả đầy đủ cho **8 use case trọng yếu** — chọn theo tiêu chí: có `«include»`/`«extend»` thật,
có quy tắc nghiệp vụ được CSDL cưỡng chế, hoặc là điểm khác biệt của đề tài.

Các use case còn lại trong [`07-use-case-model.md`](07-use-case-model.md) theo cùng khuôn mẫu ở §0.

---

## 0. Khuôn mẫu đặc tả

| Mục | Ý nghĩa |
| --- | --- |
| **Mã / Tên** | Định danh duy nhất |
| **Actor chính** | Người khởi xướng, có mục tiêu |
| **Actor phụ** | Hệ thống ngoài được gọi tới |
| **Tiền điều kiện** | Phải đúng *trước khi* bắt đầu |
| **Hậu điều kiện** | Đảm bảo đúng *sau khi* kết thúc thành công |
| **Kích hoạt** | Sự kiện mở màn |
| **Luồng chính** | Kịch bản thành công |
| **Luồng thay thế** | Rẽ nhánh vẫn thành công (`3a`, `3b`…) |
| **Luồng ngoại lệ** | Thất bại (`E1`, `E2`…) |
| **Quy tắc nghiệp vụ** | Ràng buộc, kèm nơi cưỡng chế |

---

## UC-01 — Đăng ký tài khoản

| | |
| --- | --- |
| **Actor chính** | Khách |
| **Actor phụ** | Dịch vụ thông báo |
| **Quan hệ** | `«include»` UC-04 Xác thực email |
| **Tiền điều kiện** | Chưa đăng nhập |
| **Hậu điều kiện** | Bản ghi `users` được tạo, `email_verified_at IS NULL` cho tới khi xác thực |

**Luồng chính**

1. Khách mở trang đăng ký.
2. Nhập email, mật khẩu, họ tên.
3. Hệ thống kiểm tra email chưa tồn tại.
4. Hệ thống băm mật khẩu và tạo bản ghi `users` với `role='learner'`, `status='active'`.
5. **«include» UC-04** — gửi email xác thực.
6. Hệ thống thông báo kiểm tra hộp thư.

**Luồng thay thế**

- *4a.* Khách đăng ký bằng OAuth → `password_hash` để NULL, `email_verified_at` gán ngay.

**Luồng ngoại lệ**

- *E1.* Email đã tồn tại → báo lỗi, không tiết lộ trạng thái tài khoản *(tránh dò tài khoản)*.
- *E2.* Gửi email thất bại → tài khoản vẫn được tạo, cho phép gửi lại. **Không** rollback.

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Cưỡng chế tại |
| --- | --- | --- |
| BR-01 | Email là duy nhất, không phân biệt hoa thường | `users.email citext UNIQUE` |
| BR-02 | `handle` chỉ gồm `a-z 0-9 _ -`, 3–30 ký tự | CHECK `users_handle_format` |
| BR-03 | Tài khoản không bao giờ xoá cứng | quy ước: dùng `status='deleted'` |

---

## UC-20 — Học bài (mở lesson)

| | |
| --- | --- |
| **Actor chính** | Học viên |
| **Quan hệ** | `«include»` UC-21 · được `«extend»` bởi UC-24 |
| **Tiền điều kiện** | Đã đăng nhập; đã ghi danh khoá học chứa bài |
| **Hậu điều kiện** | `lesson_progress` tồn tại với `status ∈ {in_progress, completed}` |

**Luồng chính**

1. Học viên chọn một bài trong danh sách chương.
2. **«include» UC-21** — hệ thống xác định bài có mở khoá cho học viên này không.
3. Hệ thống nạp nội dung từ Mongo `lesson_contents` theo `lessons.content_ref`.
4. Nếu chưa có bản ghi tiến độ → tạo `lesson_progress(status='in_progress', started_at=now())`.
5. Hiển thị nội dung, mục tiêu bài học và điều hướng bài trước/sau.

**Luồng thay thế**

- *3a.* Bài dạng `video` → khôi phục vị trí xem từ `last_position_seconds`.
- *3b.* Bài dạng `exercise` và `lessons.exercise_id IS NOT NULL` → mở workspace (chuyển UC-33).
- *3c.* `content_ref IS NULL` → hiển thị trạng thái "đang biên soạn".

**Luồng ngoại lệ**

- *E1.* UC-21 trả `false` → hiển thị lý do khoá kèm **danh sách bài tiên quyết còn thiếu**, không
  mở nội dung.
- *E2.* Không tìm thấy tài liệu Mongo dù `content_ref` có giá trị → báo lỗi nội dung, ghi log.
  *(Không thể xảy ra với bài đã xuất bản — xem BR-11.)*

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Cưỡng chế tại |
| --- | --- | --- |
| BR-10 | Bài `is_preview = true` xem được mà không cần ghi danh | logic ứng dụng |
| BR-11 | Nội dung đã xuất bản luôn có thân bài | CHECK `..._published_needs_content` |

---

## UC-21 — Kiểm tra điều kiện mở khoá  *(included)*

Use case **quan trọng nhất** của đề tài: thay thế hoàn toàn cờ `isLocked` cũ vốn được gán cứng
trên dữ liệu và không thể khác nhau giữa các học viên.

| | |
| --- | --- |
| **Actor chính** | *(không có — luôn được include)* |
| **Tiền điều kiện** | Bài học tồn tại |
| **Hậu điều kiện** | Trả về `true`/`false` + danh sách điều kiện chưa thoả |

**Luồng chính**

1. Xác định khoá học chứa bài (`lessons.course_id`).
2. Xác định **chế độ học hiệu lực**:
   `COALESCE(course_enrollments.mode_override, courses.progression_mode)`.
3. Rẽ theo chế độ:

| Chế độ | Quy tắc |
| --- | --- |
| `free` | Trả `true` ngay — mọi bài đều mở |
| `linear` | Trả `true` khi **mọi bài không tuỳ chọn đứng trước** (theo `chapter.position`, `lesson.position`) đã hoàn thành. **Không đọc bảng cạnh** |
| `graph` | Trả `true` khi không có cạnh tiên quyết nào, **hoặc** có ít nhất một `group_index` mà **toàn bộ** cạnh trong nhóm đó đã hoàn thành |

**Ví dụ đánh giá `graph` (DNF)**

```
Cạnh của "Class và Object":  (Kiểu dữ liệu, group 0)
                             (Toán tử,      group 0)
→ group 0 là AND  →  phải hoàn thành CẢ HAI
```

```
Cạnh của "Rate limiter":     (JWT guard,      group 0)
                             (API pagination, group 1)
→ hai group khác nhau là OR  →  chỉ cần MỘT
```

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Cưỡng chế tại |
| --- | --- | --- |
| BR-20 | `position` **không** mang ý nghĩa tiên quyết ở chế độ `graph` | thiết kế: hai khái niệm tách bảng |
| BR-21 | "Hoàn thành" của bài học = `lesson_progress.status='completed'` | `fn_lesson_available` |
| BR-22 | Bài `is_optional` không chặn tiến độ | mệnh đề `NOT l.is_optional` |

**Hiện thực:** `fn_lesson_available(user_id, lesson_id)` — migration `0011`.
Kiểm chứng: `postgres/verify.sql` mục B.

---

## UC-26 / UC-31 — Chọn chế độ học có ràng buộc hoặc tự do

Hiện thực trực tiếp yêu cầu *"hỗ trợ cả học tuần tự lẫn học tự do, không nhân bản nội dung"*.

| | |
| --- | --- |
| **Actor chính** | Học viên |
| **Quan hệ** | `«extend»` UC-21 (bài học) / UC-32 (bài tập) |
| **Tiền điều kiện** | Đã ghi danh khoá học hoặc bộ bài tập |
| **Hậu điều kiện** | `mode_override` được ghi; **không** bản ghi nội dung nào bị sửa |

**Luồng chính**

1. Học viên mở tuỳ chọn chế độ học.
2. Hệ thống hiển thị chế độ mặc định do người tạo nội dung đặt.
3. Học viên chọn *Tuần tự* / *Theo sơ đồ* / *Tự do*.
4. Ghi vào `course_enrollments.mode_override` hoặc
   `exercise_set_enrollments.progression_mode_override`.
5. Mọi lần kiểm tra mở khoá sau đó dùng giá trị mới.

**Luồng thay thế**

- *3a.* Chọn "theo mặc định" → ghi `NULL`, kế thừa lại chế độ của nội dung.

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Ghi chú |
| --- | --- | --- |
| BR-30 | Đổi chế độ **không** ảnh hưởng học viên khác | `mode_override` nằm trên bản ghi ghi danh |
| BR-31 | Đổi chế độ **không** xoá cạnh tiên quyết | ở `free`, cạnh chỉ còn giá trị gợi ý |
| BR-32 | Không nhân bản nội dung để phục vụ hai chế độ | cùng một `exercises` xuất hiện ở bộ `graph` và bộ `free` |

---

## UC-35 — Nộp bài

| | |
| --- | --- |
| **Actor chính** | Học viên |
| **Actor phụ** | Hệ thống chấm bài |
| **Quan hệ** | `«include»` UC-36 · được `«extend»` bởi UC-37, UC-72 |
| **Tiền điều kiện** | Bài tập đang mở khoá (UC-32); có mã nguồn |
| **Hậu điều kiện** | Có bản ghi `submissions`; `exercise_progress` được cập nhật |

**Luồng chính**

1. Học viên bấm *Nộp bài*.
2. Hệ thống xác định `attempt_number` kế tiếp cho cặp (học viên, bài tập).
3. Tạo `submissions` với `verdict='pending'`.
4. **«include» UC-36** — gửi mã nguồn + toàn bộ test case sang Hệ thống chấm bài.
5. Nhận kết quả: verdict, số test đạt, thời gian, bộ nhớ.
6. Ghi chi tiết từng test vào Mongo `submission_run_details`, lưu `run_detail_ref`.
7. Cập nhật `exercise_progress`: `attempt_count += 1`; nếu `verdict='accepted'` thì
   `status='solved'`, `first_solved_at` (nếu chưa có), `best_score`.
8. Hiển thị kết quả — test ẩn chỉ hiện *đạt/không đạt*, không lộ dữ liệu vào/ra.

**Luồng thay thế**

- *2a.* **«extend» UC-37** — quá `due_at` và `allow_late_submission = true`
  → đặt `submissions.is_late = true`, vẫn chấm bình thường.
- *8a.* **«extend» UC-72** — verdict ≠ `accepted`, học viên yêu cầu AI phân tích lỗi.

**Luồng ngoại lệ**

- *E1.* Quá `due_at` và `allow_late_submission = false` → từ chối nộp.
- *E2.* Vượt `attempt_limit` của bài được giao → từ chối.
- *E3.* Lỗi biên dịch → `verdict='compile_error'`, `score=0`; **vẫn lưu** bản nộp.
- *E4.* Hệ thống chấm không phản hồi → giữ `verdict='pending'`, cho phép chấm lại. Bản nộp
  **không** bị mất.

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Cưỡng chế tại |
| --- | --- | --- |
| BR-40 | `attempt_number` duy nhất theo (học viên, bài tập) | UNIQUE `(user_id, exercise_id, attempt_number)` |
| BR-41 | `passed_tests ≤ total_tests` | CHECK `submissions_passed_le_total` |
| BR-42 | Không xoá bài tập còn bản nộp | FK `ON DELETE RESTRICT` |
| BR-43 | Bản nộp nhóm có `assignment_id`; luyện tập tự do thì NULL | cột nullable — không cần cột phân loại |
| BR-44 | Chi tiết chấm tự hết hạn sau 180 ngày; verdict thì không | TTL index Mongo |

---

## UC-47 / UC-48 — Thiết lập điều kiện tiên quyết & kiểm tra chu trình

| | |
| --- | --- |
| **Actor chính** | Quản trị viên |
| **Quan hệ** | UC-47 `«include»` UC-48 |
| **Tiền điều kiện** | Hai đối tượng cùng phạm vi (cùng khoá / cùng lộ trình / cùng bộ) |
| **Hậu điều kiện** | Cạnh được ghi, hoặc bị từ chối kèm lý do; đồ thị luôn là DAG |

**Luồng chính**

1. Quản trị viên chọn đối tượng cần đặt điều kiện (bài học / chương / khoá / bài tập).
2. Chọn một hoặc nhiều đối tượng tiên quyết.
3. Chọn quan hệ logic:
   - *Tất cả* → cùng một `group_index`
   - *Một trong số* → mỗi cái một `group_index` khác nhau
4. **«include» UC-48** — CSDL kiểm tra chu trình trước khi ghi.
5. Ghi cạnh vào bảng `*_prerequisites` tương ứng.

**Luồng ngoại lệ**

| Mã | Trường hợp | Cơ chế chặn | SQLSTATE |
| --- | --- | --- | --- |
| E1 | Tự tham chiếu (A→A) | CHECK `*_no_self_reference` | `23514` |
| E2 | Cạnh trùng | PRIMARY KEY | `23505` |
| E3 | **Chu trình trực tiếp** (A→B rồi B→A) | trigger `fn_prevent_dependency_cycle` | `23514` |
| E4 | **Chu trình gián tiếp** (A→B→C→A) | cùng trigger, duyệt đệ quy | `23514` |
| E5 | Khác phạm vi (bài của khoá khác) | FOREIGN KEY tổ hợp | `23503` |
| E6 | Đối tượng không tồn tại | FOREIGN KEY | `23503` |
| E7 | Trỏ tới nội dung đã lưu trữ | trigger `fn_reject_archived_*` | `23514` |

**Cách phát hiện chu trình:** trước khi thêm *"S phải trước T"*, duyệt xuôi từ **T** xem có tới
được **S** không. Nếu có thì cạnh mới khép vòng. Dùng `UNION` (không phải `UNION ALL`) nên dữ
liệu lỗi sẵn có cũng không làm treo.

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Ghi chú |
| --- | --- | --- |
| BR-50 | Đồ thị tiên quyết luôn là DAG | không có ngoại lệ |
| BR-51 | Điều kiện của lộ trình trỏ tới `roadmap_courses.id`, không phải `courses.id` | để cùng một khoá bị khoá ở lộ trình này, tự do ở lộ trình khác |
| BR-52 | Cạnh bài tập gắn với **một bộ** | cùng bài có thể bị khoá ở bộ A, tự do ở bộ B |

Kiểm chứng: `postgres/verify.sql` mục C — cả 7 trường hợp đều được khẳng định là bị từ chối.

---

## UC-53 — Tải tài liệu lên nhóm

| | |
| --- | --- |
| **Actor chính** | Thành viên nhóm |
| **Actor phụ** | Dịch vụ AI |
| **Quan hệ** | `«include»` UC-54 Tiền kiểm AI, UC-5B Ghi nhận hoạt động |
| **Tiền điều kiện** | Là thành viên `active`; **quyền `uploadDoc` = true** |
| **Hậu điều kiện** | `group_documents` được tạo với hai trục trạng thái độc lập |

**Luồng chính**

1. Thành viên chọn tệp hoặc dán liên kết, nhập tiêu đề và chủ đề.
2. Hệ thống kiểm tra quyền `uploadDoc` hiệu lực *(quyền vai trò chồng quyền cá nhân)*.
3. Lưu tệp vào kho đối tượng, ghi `storage_key`; hoặc ghi `url` nếu là liên kết.
4. **«include» UC-54** — gửi nội dung cho Dịch vụ AI tiền kiểm → nhận `ai_verdict`.
5. Tạo `group_documents` với `status='pending'` và `ai_verdict` vừa nhận.
6. **«include» UC-5B** — ghi hoạt động vào `group_activities`.
7. Tài liệu vào hàng đợi duyệt (UC-55).

**Luồng thay thế**

- *4a.* `ai_verdict='valid'` và nhóm bật tự động duyệt → `status='published'` ngay.
- *4b.* Dịch vụ AI không phản hồi → `ai_verdict='valid'` mặc định, đánh dấu cần người xem kỹ.
  **Không** chặn việc tải lên.

**Luồng ngoại lệ**

- *E1.* Không có quyền `uploadDoc` → từ chối.
- *E2.* Loại tệp không hỗ trợ hoặc quá dung lượng → từ chối trước khi lưu.

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Cưỡng chế tại |
| --- | --- | --- |
| BR-60 | Tài liệu `Link` phải có `url`; tài liệu tệp phải có `storage_key` | CHECK `group_documents_body_present` |
| BR-61 | `status` (người duyệt) và `ai_verdict` (máy) là **hai trục độc lập** | hai cột riêng |
| BR-62 | Chỉ tài liệu `published` mới hiện với thành viên thường | logic ứng dụng |

---

## UC-58 — Chấm & phản hồi bài nộp của nhóm

| | |
| --- | --- |
| **Actor chính** | Phó nhóm *(hoặc Trưởng nhóm qua kế thừa)* |
| **Tiền điều kiện** | **Quyền `reviewSubmission` = true**; tồn tại bản nộp |
| **Hậu điều kiện** | `assignments.review_status` khác `pending`; có `reviewed_by`, `reviewed_at` |

**Luồng chính**

1. Người duyệt mở hàng đợi bài chờ chấm của nhóm.
2. Chọn một bài, xem mã nguồn và kết quả chấm tự động.
3. Nhập nhận xét, chọn *Đạt* hoặc *Cần sửa*.
4. Cập nhật `assignments`: `review_status`, `feedback`, `reviewed_by`, `reviewed_at`.
5. **«include» UC-5B** — ghi hoạt động.

**Luồng thay thế**

- *3a.* Chọn *Cần sửa* → `review_status='needsfix'`, thành viên nộp lại nếu `allow_retry=true`.

**Luồng ngoại lệ**

- *E1.* Không có quyền `reviewSubmission` → từ chối. *Lưu ý: một phó nhóm cụ thể có thể bị gỡ
  quyền này qua `group_member_permissions`.*
- *E2.* Tự chấm bài của chính mình → từ chối *(quy tắc ứng dụng)*.

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Cưỡng chế tại |
| --- | --- | --- |
| BR-70 | `review_status='pending'` ⟺ `reviewed_at IS NULL` | CHECK `assignments_reviewed_consistency` |
| BR-71 | Bài nộp và người chấm phải cùng nhóm | FK tổ hợp `assignments_member_in_group` |
| BR-72 | Trưởng nhóm luôn có mọi quyền | không lưu trong `group_role_permissions`; bộ phân giải mặc định `true` |

---

## UC-51 — Tham gia nhóm bằng mã mời

| | |
| --- | --- |
| **Actor chính** | Học viên |
| **Tiền điều kiện** | Đã đăng nhập; chưa là thành viên nhóm đó |
| **Hậu điều kiện** | `group_members(role='member', status='active')`; `member_count` được cập nhật |

**Luồng chính**

1. Học viên nhập mã mời.
2. Hệ thống tra `study_groups.invite_code` *(không phân biệt hoa thường)*.
3. Kiểm tra nhóm `status='active'`.
4. Tạo `group_members` với `role='member'`.
5. Trigger cập nhật `study_groups.member_count`.

**Luồng ngoại lệ**

- *E1.* Mã không tồn tại → báo lỗi chung, **không** tiết lộ nhóm có tồn tại hay không.
- *E2.* Đã là thành viên → chuyển thẳng vào nhóm.
- *E3.* Nhóm đã lưu trữ → từ chối.

**Quy tắc nghiệp vụ**

| Mã | Quy tắc | Cưỡng chế tại |
| --- | --- | --- |
| BR-80 | Mã mời duy nhất, 5–12 ký tự chữ và số | UNIQUE + CHECK `study_groups_invite_code_format` |
| BR-81 | Mỗi người chỉ một bản ghi trong một nhóm | UNIQUE `(group_id, user_id)` |
| BR-82 | Mỗi nhóm đúng một trưởng nhóm | UNIQUE INDEX `uq_group_members_single_owner` |

---

## Phụ lục — Bảng quy tắc nghiệp vụ

| Mã | Tóm tắt | Nơi cưỡng chế |
| --- | --- | --- |
| BR-01…03 | Định danh tài khoản | UNIQUE, CHECK |
| BR-10…11 | Truy cập nội dung | CHECK + ứng dụng |
| BR-20…22 | Điều kiện mở khoá | `fn_lesson_available` |
| BR-30…32 | Chế độ học | `mode_override` |
| BR-40…44 | Nộp bài & chấm | UNIQUE, CHECK, FK RESTRICT, TTL |
| BR-50…52 | Toàn vẹn đồ thị phụ thuộc | trigger + FK tổ hợp |
| BR-60…62 | Tài liệu nhóm | CHECK |
| BR-70…72 | Duyệt bài & phân quyền | CHECK + FK tổ hợp |
| BR-80…82 | Thành viên nhóm | UNIQUE + partial index |

**36/40 quy tắc được cưỡng chế ở tầng CSDL**, không phụ thuộc vào tầng ứng dụng nhớ kiểm tra —
đúng nguyên tắc đã đặt ra ở [`04-design-decisions.md`](04-design-decisions.md).
