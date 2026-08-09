// Generates docs/05-schema-reference.md from the LIVE database catalog, so the reference can
// never drift from the migrations.
//
//   node scripts/gen-schema-doc.js <dumpDir> > docs/05-schema-reference.md
//
// <dumpDir> holds cols.txt / fks.txt / cons.txt produced by scripts/dump-catalog.sh.

const fs = require("fs");
const path = require("path");

const dir = process.argv[2];
const read = (f) =>
  fs.readFileSync(path.join(dir, f), "utf8").split(/\r?\n/).filter(Boolean).map((l) => l.split("|"));

const cols = read("cols.txt");   // table | attnum | name | type | notnull | default
const fks = read("fks.txt");     // table | conname | cols | reftable | refcols | ondelete
const cons = read("cons.txt");   // table | contype | conname | definition

// --- context grouping + purpose, written by hand; everything else is generated -------------
const GROUPS = [
  ["Danh tính & cá nhân hoá", [
    ["users", "Tài khoản nền tảng. Không xoá cứng — dùng `status='deleted'` để bài viết/bài nộp vẫn còn tác giả hợp lệ."],
    ["user_stats", "**CACHE** tổng hợp hoạt động (XP, số bài giải, streak). Tách khỏi `users` vì ghi rất thường xuyên."],
    ["learning_preferences", "Kết quả khảo sát onboarding — đầu vào cho thuật toán gợi ý lộ trình."],
    ["study_schedule_slots", "Khung giờ học từng ngày trong tuần. Là bảng thật (không phải JSON) để scheduler truy vấn được “ai học lúc 19:00 thứ 2”."],
  ]],
  ["Từ điển dùng chung", [
    ["technologies", "Danh mục công nghệ chuẩn hoá, dùng chung cho roadmap/course/exercise/preference."],
    ["tags", "Nhãn chủ đề tự do cho bài tập và bài viết."],
    ["companies", "Công ty gắn với bài tập phỏng vấn (mục “Nhu cầu tuyển dụng”)."],
  ]],
  ["Nội dung học", [
    ["roadmaps", "Lộ trình học — tập hợp nhiều khoá theo một hướng nghề nghiệp."],
    ["roadmap_outcomes", "Danh sách “học xong làm được gì”, có thứ tự."],
    ["roadmap_audiences", "Đối tượng phù hợp với lộ trình, có thứ tự."],
    ["roadmap_technologies", "N-N roadmap ↔ công nghệ."],
    ["courses", "Khoá học. `progression_mode` quyết định cách khoá chương/bài bên trong."],
    ["course_outcomes", "Mục tiêu đầu ra của khoá, có thứ tự."],
    ["course_technologies", "N-N khoá học ↔ công nghệ."],
    ["course_reviews", "Đánh giá của học viên — nguồn sự thật cho `courses.rating_avg`."],
    ["roadmap_courses", "**Thực thể hạng nhất**, không phải bảng nối thuần. Vị trí và điều kiện mở khoá thuộc về “khoá này trong lộ trình này”."],
    ["chapters", "Chương trong khoá học. `position` chỉ là thứ tự hiển thị."],
    ["lessons", "Bài học. `course_id` là cột phi chuẩn hoá nhưng được FK kép chứng minh luôn khớp chương cha."],
  ]],
  ["Bài tập", [
    ["exercises", "**Xương sống quan hệ** của bài tập. Phần nội dung nằm ở MongoDB qua `content_ref`."],
    ["exercise_tags", "N-N bài tập ↔ nhãn."],
    ["exercise_technologies", "N-N bài tập ↔ công nghệ."],
    ["exercise_companies", "N-N bài tập ↔ công ty."],
    ["exercise_sets", "Bộ bài tập được tuyển chọn (“Top 100 phỏng vấn”, “Nhập môn thuật toán”)."],
    ["exercise_set_items", "Thành viên của bộ + thứ tự hiển thị."],
    ["exercise_set_enrollments", "Học viên tham gia bộ, kèm quyền tự chọn bật/tắt ràng buộc thứ tự."],
  ]],
  ["Quan hệ phụ thuộc (điều kiện tiên quyết)", [
    ["roadmap_course_prerequisites", "Trình tự khoá học **theo từng lộ trình**. Trỏ tới `roadmap_courses.id`."],
    ["course_prerequisites", "Điều kiện **nội tại** của khoá, độc lập với mọi lộ trình."],
    ["chapter_prerequisites", "Phụ thuộc giữa các chương trong cùng một khoá."],
    ["lesson_prerequisites", "Phụ thuộc giữa các bài trong cùng một khoá (cho phép xuyên chương)."],
    ["exercise_prerequisites", "Phụ thuộc giữa bài tập, **phạm vi theo bộ** — nên cùng một bài có thể bị khoá ở bộ này và tự do ở bộ khác."],
  ]],
  ["Ghi danh & tiến độ", [
    ["roadmap_enrollments", "Ghi danh lộ trình + **cache** tiến độ, do trigger cập nhật."],
    ["course_enrollments", "Ghi danh khoá học + **cache** tiến độ. `mode_override` cho phép học viên tự chọn chế độ."],
    ["lesson_progress", "**NGUỒN SỰ THẬT** cho mọi phần trăm tiến độ."],
    ["exercise_progress", "Trạng thái luyện tập của từng học viên (todo/attempted/solved, yêu thích)."],
  ]],
  ["Nhóm học tập & bài nộp", [
    ["study_groups", "Nhóm học tập, có mã mời duy nhất."],
    ["group_members", "Thành viên nhóm + vai trò. Ràng buộc mỗi nhóm đúng 1 owner."],
    ["group_role_permissions", "Quyền mặc định theo vai trò, cấu hình riêng từng nhóm. Owner không lưu (luôn full quyền)."],
    ["group_member_permissions", "Ghi đè quyền cho từng cá nhân, chồng lên quyền vai trò."],
    ["group_documents", "Tài liệu nhóm. `status` (người duyệt) và `ai_verdict` (AI tiền kiểm) là **hai trục độc lập**."],
    ["group_exercises", "Việc xuất bản một bài tập vào nhóm: hạn nộp, số lần thử, giai đoạn."],
    ["assignments", "Nghĩa vụ của một thành viên với một bài đã giao."],
    ["submissions", "Bài nộp. `assignment_id` NULL = luyện tập tự do, có giá trị = nộp cho nhóm."],
    ["group_activities", "Nhật ký hoạt động của nhóm."],
  ]],
  ["Nội dung biên tập", [
    ["articles", "Bài viết. Phần thân (sections) nằm ở MongoDB qua `content_ref`."],
  ]],
];

const desc = new Map();
for (const [, rows] of GROUPS) for (const [t, d] of rows) desc.set(t, d);

const allTables = [...new Set(cols.map((c) => c[0]))].sort();
const missing = allTables.filter((t) => !desc.has(t));
if (missing.length) throw new Error("thiếu mô tả cho bảng: " + missing.join(", "));

const by = (rows, i) => rows.reduce((m, r) => ((m[r[i]] ??= []).push(r), m), {});
const colsBy = by(cols, 0);
const fksBy = by(fks, 0);
const consBy = by(cons, 0);
const inbound = fks.reduce((m, r) => ((m[r[3]] ??= []).push(r), m), {});

const esc = (s) => (s || "").replace(/\|/g, "\\|");
const out = [];
const P = (s = "") => out.push(s);

P("# Tham chiếu Schema — Toàn bộ bảng & quan hệ");
P();
P("> Sinh tự động từ database đang chạy bằng `scripts/dump-catalog.sh` + `scripts/gen-schema-doc.js`.");
P("> **Không sửa tay** — chạy lại generator sau mỗi migration.");
P();
P(`PostgreSQL: **${allTables.length} bảng**, **${fks.length} khoá ngoại**, ` +
  `**${cons.filter((c) => c[1] === "c").length} ràng buộc CHECK**.`);
P();
P("Xem thêm: [mô hình miền](01-domain-model.md) · [mô hình phụ thuộc](02-dependency-model.md) · [MongoDB](03-mongodb-model.md)");
P();

// ---- 1. mục lục theo ngữ cảnh
P("## 1. Danh sách bảng theo ngữ cảnh");
P();
for (const [group, rows] of GROUPS) {
  P(`### ${group}`);
  P();
  P("| Bảng | Vai trò |");
  P("| --- | --- |");
  for (const [t, d] of rows) P(`| [\`${t}\`](#${t}) | ${d} |`);
  P();
}

// ---- 2. sơ đồ quan hệ tổng
P("## 2. Bản đồ quan hệ");
P();
P("Mũi tên đi từ bảng **chứa khoá ngoại** tới bảng **được tham chiếu**.");
P();
P("```mermaid");
P("graph LR");
const skip = new Set(["users"]); // users bị tham chiếu khắp nơi, vẽ hết sẽ rối
const seen = new Set();
for (const [src, , , tgt] of fks) {
  if (skip.has(tgt)) continue;
  const key = src + "->" + tgt;
  if (seen.has(key)) continue;
  seen.add(key);
  P(`  ${src} --> ${tgt}`);
}
P("```");
P();
P("*(`users` được lược khỏi sơ đồ vì gần như mọi bảng đều tham chiếu tới nó.)*");
P();

// ---- 3. chi tiết từng bảng
P("## 3. Chi tiết từng bảng");
P();
for (const [group, rows] of GROUPS) {
  P(`---`);
  P();
  P(`## ${group}`);
  P();
  for (const [t, d] of rows) {
    P(`### \`${t}\``);
    P();
    P(d);
    P();

    P("| # | Cột | Kiểu | Null | Mặc định |");
    P("| --- | --- | --- | --- | --- |");
    for (const [, n, name, type, nn, def] of colsBy[t] || []) {
      P(`| ${n} | \`${name}\` | \`${esc(type)}\` | ${nn ? "NOT NULL" : "" } | ${def ? "`" + esc(def) + "`" : ""} |`);
    }
    P();

    const c = consBy[t] || [];
    const pk = c.filter((x) => x[1] === "p");
    const uq = c.filter((x) => x[1] === "u");
    const ck = c.filter((x) => x[1] === "c");

    if (pk.length || uq.length) {
      P("**Khoá & ràng buộc duy nhất**");
      P();
      for (const [, , name, defn] of pk) P(`- \`${name}\` — ${esc(defn)}`);
      for (const [, , name, defn] of uq) P(`- \`${name}\` — ${esc(defn)}`);
      P();
    }

    const outF = fksBy[t] || [];
    if (outF.length) {
      P("**Khoá ngoại (đi ra)**");
      P();
      P("| Cột | → Bảng đích | ON DELETE |");
      P("| --- | --- | --- |");
      for (const [, , sc, rt, rc, od] of outF) {
        P(`| \`${esc(sc)}\` | \`${rt}\` (\`${esc(rc)}\`) | ${od} |`);
      }
      P();
    }

    const inF = inbound[t] || [];
    if (inF.length) {
      P("**Được tham chiếu bởi**");
      P();
      P(inF.map(([s, , sc]) => `\`${s}.${sc}\``).join(" · "));
      P();
    }

    if (ck.length) {
      P("<details><summary><strong>Ràng buộc CHECK</strong> (" + ck.length + ")</summary>");
      P();
      for (const [, , name, defn] of ck) P(`- \`${name}\` — \`${esc(defn)}\``);
      P();
      P("</details>");
      P();
    }
  }
}

// ---- 4. ma trận khoá ngoại
P("---");
P();
P("## 4. Toàn bộ khoá ngoại");
P();
P("| Bảng nguồn | Cột | Bảng đích | ON DELETE |");
P("| --- | --- | --- | --- |");
for (const [src, , sc, tgt, tc, od] of fks) {
  P(`| \`${src}\` | \`${esc(sc)}\` | \`${tgt}\` (\`${esc(tc)}\`) | ${od} |`);
}
P();

// ---- 5. ghi chú ON DELETE
P("## 5. Ngữ nghĩa xoá");
P();
P("| Hành vi | Số lượng | Dùng khi |");
P("| --- | --- | --- |");
const tally = fks.reduce((m, r) => ((m[r[5]] = (m[r[5]] || 0) + 1), m), {});
const why = {
  CASCADE: "Bản ghi con không có ý nghĩa nếu thiếu cha (chương thuộc khoá, cạnh phụ thuộc, tiến độ thuộc người dùng).",
  RESTRICT: "Xoá phải thất bại rõ ràng thay vì âm thầm phá cấu trúc (khoá học đang nằm trong lộ trình, bài tập đã có bài nộp).",
  "SET NULL": "Quan hệ là tuỳ chọn; mất tham chiếu vẫn giữ được bản ghi (tác giả, người duyệt, tài liệu tham khảo).",
  "NO ACTION": "Mặc định của PostgreSQL, tương đương RESTRICT nhưng kiểm tra ở cuối câu lệnh.",
};
for (const [k, v] of Object.entries(tally).sort((a, b) => b[1] - a[1])) {
  P(`| \`${k}\` | ${v} | ${why[k] || ""} |`);
}
P();

process.stdout.write(out.join("\n") + "\n");
