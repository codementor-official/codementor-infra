-- 0014 — Keycloak trở thành nhà cung cấp danh tính.
--
-- Xác thực (kể cả đăng nhập bằng Google/GitHub/Facebook) do Keycloak đảm nhiệm.
-- Bảng `users` không còn là nguồn sự thật về danh tính — nó là **hình chiếu** của tài
-- khoản Keycloak, giữ phần dữ liệu thuộc về sản phẩm: tên hiển thị, handle, trạng thái.

BEGIN;

-- `sub` của Keycloak. Ổn định suốt vòng đời tài khoản, kể cả khi người dùng đổi email.
-- Nullable vì dữ liệu seed/demo không có tài khoản Keycloak tương ứng — những hàng đó
-- đơn giản là không đăng nhập được, vì tra cứu lúc xác thực đi qua cột này.
ALTER TABLE users ADD COLUMN external_id citext UNIQUE;

COMMENT ON COLUMN users.external_id IS
  'Định danh ở nhà cung cấp danh tính (Keycloak sub). NULL = tài khoản nội bộ/seed, không đăng nhập được.';

-- Credential do Keycloak giữ. Để lại cột này chỉ mời gọi việc vô tình ghi mật khẩu
-- vào hệ thống của mình, tạo ra hai nguồn sự thật.
ALTER TABLE users DROP COLUMN password_hash;

-- Tra cứu theo external_id chạy ở MỌI request đã xác thực → phải có index.
-- (UNIQUE ở trên đã tạo index, dòng này chỉ ghi lại chủ ý.)

COMMIT;
