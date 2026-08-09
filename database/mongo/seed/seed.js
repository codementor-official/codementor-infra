// Mongo seed. _id values match the `content_ref` columns written by
// postgres/seed/0001_seed.sql, so the two stores line up after a clean init.
//
//   mongosh "$MONGO_URI" --file mongo/seed/seed.js

/* global db, print */

const targetDb = (typeof process !== "undefined" && process.env && process.env.MONGO_DB) || "codementor";
const database = db.getSiblingDB(targetDb);
const now = new Date();

const PG = {
  // exercises
  linearSearch: "10000000-0000-4000-8000-000000000001",
  binarySearch: "10000000-0000-4000-8000-000000000002",
  bubbleSort: "10000000-0000-4000-8000-000000000003",
  mergeSort: "10000000-0000-4000-8000-000000000004",
  bisect: "10000000-0000-4000-8000-000000000005",
  jwtGuard: "10000000-0000-4000-8000-000000000006",
  pagination: "10000000-0000-4000-8000-000000000007",
  rateLimiter: "10000000-0000-4000-8000-000000000008",
};

// ---------------------------------------------------------------------------
// exercise_contents
// ---------------------------------------------------------------------------
const exerciseDocs = [
  {
    _id: ObjectId("65f00000000000000000ee01"),
    exerciseId: PG.linearSearch,
    kind: "code",
    statement:
      "Cho mảng `a` gồm `n` số nguyên và giá trị `x`. In ra chỉ số đầu tiên của `x` trong mảng, hoặc `-1` nếu không tìm thấy.",
    constraints: ["1 ≤ n ≤ 10^5", "-10^9 ≤ a[i], x ≤ 10^9"],
    examples: [
      { input: "5\n3 7 1 9 4\n9", output: "3", explanation: "a[3] = 9" },
      { input: "3\n1 2 3\n8", output: "-1", explanation: "không có phần tử nào bằng 8" },
    ],
    testCases: [
      { order: 1, input: "5\n3 7 1 9 4\n9", expected: "3", visibility: "public", generated: false, weight: 1 },
      { order: 2, input: "3\n1 2 3\n8", expected: "-1", visibility: "public", generated: false, weight: 1 },
      { order: 3, input: "1\n42\n42", expected: "0", visibility: "hidden", generated: true, weight: 1 },
      { order: 4, input: "4\n5 5 5 5\n5", expected: "0", visibility: "hidden", generated: true, weight: 1 },
    ],
    languages: [
      { id: "python", label: "Python 3.11", monaco: "python", starterCode: "def solve(a, x):\n    # TODO\n    pass\n" },
      { id: "java", label: "Java 21", monaco: "java", starterCode: "class Main {\n  static int solve(int[] a, int x) {\n    // TODO\n    return -1;\n  }\n}\n" },
    ],
    evaluation: { checker: "trimmed", stopOnFirstFailure: false },
    hints: [
      { order: 1, text: "Duyệt mảng từ trái sang phải và dừng ngay khi gặp phần tử bằng x.", xpPenalty: 5 },
    ],
    createdAt: now,
    updatedAt: now,
  },
  {
    _id: ObjectId("65f00000000000000000ee02"),
    exerciseId: PG.binarySearch,
    kind: "code",
    statement:
      "Cho mảng đã sắp xếp tăng dần `a` và giá trị `x`. Tìm chỉ số của `x` bằng thuật toán tìm kiếm nhị phân, độ phức tạp O(log n).",
    constraints: ["1 ≤ n ≤ 10^6", "Mảng đã được sắp xếp tăng dần", "Giới hạn thời gian: 1 giây"],
    examples: [{ input: "5\n1 3 5 7 9\n7", output: "3" }],
    testCases: [
      { order: 1, input: "5\n1 3 5 7 9\n7", expected: "3", visibility: "public", generated: false, weight: 1 },
      { order: 2, input: "5\n1 3 5 7 9\n2", expected: "-1", visibility: "hidden", generated: true, weight: 1 },
      { order: 3, input: "1\n1\n1", expected: "0", visibility: "hidden", generated: true, weight: 1 },
    ],
    languages: [
      { id: "python", label: "Python 3.11", monaco: "python", starterCode: "def solve(a, x):\n    pass\n" },
    ],
    evaluation: { checker: "trimmed", stopOnFirstFailure: false },
    hints: [{ order: 1, text: "Giữ hai biên lo, hi và so sánh với phần tử giữa.", xpPenalty: 10 }],
    createdAt: now,
    updatedAt: now,
  },
];

// The remaining exercises get a minimal but valid body so `status='published'` in postgres
// (which requires content_ref) is honest.
const minimal = [
  ["65f00000000000000000ee03", PG.bubbleSort, "Cài đặt thuật toán sắp xếp nổi bọt cho mảng số nguyên."],
  ["65f00000000000000000ee04", PG.mergeSort, "Cài đặt sắp xếp trộn với độ phức tạp O(n log n)."],
  ["65f00000000000000000ee05", PG.bisect, "Dùng chia đôi trên miền số thực để tìm nghiệm với sai số 1e-6."],
  ["65f00000000000000000ee06", PG.jwtGuard, "Kiểm tra JWT, xác thực vai trò và trả về mã lỗi phù hợp."],
  ["65f00000000000000000ee07", PG.pagination, "Trả về danh sách theo trang kèm tổng số bản ghi."],
  ["65f00000000000000000ee08", PG.rateLimiter, "Giới hạn số yêu cầu trong một cửa sổ thời gian trượt."],
].map(([id, exerciseId, statement]) => ({
  _id: ObjectId(id),
  exerciseId,
  kind: "code",
  statement,
  constraints: ["Giới hạn thời gian: 1 giây"],
  testCases: [
    { order: 1, input: "1", expected: "1", visibility: "public", generated: false, weight: 1 },
  ],
  languages: [{ id: "python", label: "Python 3.11", monaco: "python", starterCode: "# TODO\n" }],
  evaluation: { checker: "trimmed", stopOnFirstFailure: false },
  createdAt: now,
  updatedAt: now,
}));

// ---------------------------------------------------------------------------
// lesson_contents
// ---------------------------------------------------------------------------
const lessonDocs = [
  {
    _id: ObjectId("65f00000000000000000ff01"),
    lessonId: "f0000000-0000-4000-8000-000000000001",
    summary: "Cấu trúc một chương trình Java, phương thức main và cách biên dịch đoạn mã đầu tiên.",
    objectives: [
      "Nhận biết class, phương thức main và câu lệnh",
      "Chạy được chương trình Java đầu tiên",
    ],
    sections: [
      {
        heading: "Một chương trình Java bắt đầu từ đâu?",
        blocks: [
          { type: "paragraph", text: "Java tổ chức mã nguồn bên trong class. Khi chạy ứng dụng console, JVM tìm tới phương thức main để bắt đầu thực thi." },
          { type: "code", label: "Main.java", language: "java", value: 'public class Main {\n  public static void main(String[] args) {\n    System.out.println("Xin chào");\n  }\n}' },
          { type: "callout", tone: "tip", text: "Tên class phải trùng với tên file." },
        ],
      },
    ],
    media: { provider: "upload", url: "https://cdn.codementor.vn/lessons/java-syntax.mp4", durationSeconds: 840 },
    createdAt: now,
    updatedAt: now,
  },
];

[
  ["65f00000000000000000ff02", "f0000000-0000-4000-8000-000000000002", "Phân biệt kiểu nguyên thủy và kiểu tham chiếu."],
  ["65f00000000000000000ff03", "f0000000-0000-4000-8000-000000000003", "Toán tử số học, so sánh và logic trong Java."],
  ["65f00000000000000000ff04", "f0000000-0000-4000-8000-000000000004", "Đọc dữ liệu bằng Scanner và in ra màn hình."],
  ["65f00000000000000000ff05", "f0000000-0000-4000-8000-000000000005", "Dùng class để mô tả dữ liệu và hành vi."],
  ["65f00000000000000000ff06", "f0000000-0000-4000-8000-000000000006", "Tái sử dụng hành vi chung qua kế thừa và đa hình."],
  ["65f00000000000000000ff07", "f0000000-0000-4000-8000-000000000007", "Vận dụng OOP vào bài toán quản lý thư viện."],
  ["65f00000000000000000ff10", "f0000000-0000-4000-8000-000000000010", "Các thẻ HTML nền tảng."],
  ["65f00000000000000000ff11", "f0000000-0000-4000-8000-000000000011", "Thẻ ngữ nghĩa và lợi ích cho SEO."],
  ["65f00000000000000000ff12", "f0000000-0000-4000-8000-000000000012", "Thuật toán là gì và vì sao cần tư duy từng bước."],
  ["65f00000000000000000ff13", "f0000000-0000-4000-8000-000000000013", "Kiểm tra nhanh khả năng nhận diện bài toán."],
].forEach(([id, lessonId, summary]) => {
  lessonDocs.push({
    _id: ObjectId(id),
    lessonId,
    summary,
    objectives: [],
    sections: [{ heading: "Nội dung", blocks: [{ type: "paragraph", text: summary }] }],
    createdAt: now,
    updatedAt: now,
  });
});

// ---------------------------------------------------------------------------
// article_contents
// ---------------------------------------------------------------------------
const articleDocs = [
  {
    _id: ObjectId("65f00000000000000000aa01"),
    articleId: "40000000-0000-4000-8000-000000000001",
    sections: [
      {
        heading: "Big-O đo cái gì?",
        paragraphs: [
          "Big-O mô tả tốc độ tăng của khối lượng công việc khi dữ liệu lớn dần, không phải thời gian chạy tuyệt đối.",
          "Hai thuật toán cùng O(n) vẫn có thể chênh nhau vài lần về thời gian thực tế.",
        ],
      },
      {
        heading: "Đếm vòng lặp trước, công thức sau",
        paragraphs: ["Một vòng lặp qua n phần tử là O(n); hai vòng lồng nhau là O(n²)."],
        code: "for i in range(n):\n    for j in range(n):\n        work()",
        language: "python",
      },
    ],
    createdAt: now,
    updatedAt: now,
  },
];

// ---------------------------------------------------------------------------
function upsertAll(collection, docs) {
  const c = database.getCollection(collection);
  let n = 0;
  for (const doc of docs) {
    c.replaceOne({ _id: doc._id }, doc, { upsert: true });
    n += 1;
  }
  print(`  ✓ ${collection.padEnd(24)} ${n} document(s)`);
}

print(`\n== codementor mongo seed → ${targetDb} ==`);
upsertAll("exercise_contents", exerciseDocs.concat(minimal));
upsertAll("lesson_contents", lessonDocs);
upsertAll("article_contents", articleDocs);
print("");
