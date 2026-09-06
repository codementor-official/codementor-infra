// Tài liệu do người soạn nội dung tự tải lên, làm nguyên liệu cho chatbot (Lecter hôm nay,
// Codey sau này). Owned by ai-service (Python).
//
// Vì sao là một collection riêng chứ không dùng luôn `ai_document_indexes` (07): khoá của bản
// index mang tên model embedding, nên đổi model là danh sách tài liệu của người dùng trông như
// rỗng. Đây đúng là cặp `group_documents` (dữ liệu) + index (cache) mà nghiệp vụ nhóm học đang
// dùng, chỉ khác chỗ lưu.
//
// Vì sao không phải một bảng PostgreSQL: tài liệu này KHÔNG có vòng đời nội dung — không nháp,
// không gửi duyệt, không công khai, không kiểm duyệt. Đó là thứ khiến Bài viết và Bài code phải
// là một bounded context Nest. Ở đây chỉ có tệp, chủ sở hữu và hạn dùng.
const definitions = [
  {
    name: "ai_documents",
    schema: {
      bsonType: "object",
      required: ["_id", "ownerId", "scope", "title", "docType", "storageKey", "sizeBytes", "revision", "createdAt"],
      properties: {
        _id: { bsonType: "string" },
        // `sub` của Keycloak, giống `ai_agent_sessions.userId` — ai-service không phân giải sang
        // `users.id`, và hai chỗ dùng hai định danh khác nhau là nguồn của lỗi "không thấy tài liệu".
        ownerId: { bsonType: "string" },
        // Bản sao của phạm vi dùng cho tầng index (`<kind>:<id>`), để xoá tài liệu là xoá được
        // đúng hàng index của nó mà không phải dựng lại chuỗi từ `ownerId`.
        scope: { bsonType: "string" },
        title: { bsonType: "string", maxLength: 500 },
        docType: { enum: ["pdf", "docx", "pptx", "txt", "md"] },
        storageKey: { bsonType: "string", maxLength: 2000 },
        sizeBytes: { bsonType: ["int", "long"] },
        contentType: { bsonType: "string", maxLength: 200 },
        // sha256 của mô tả tệp. Đổi tệp là đổi revision, và bản index cũ tự hết hiệu lực —
        // cùng cách `WorkspaceAiService.descriptor` tính cho tài liệu nhóm.
        revision: { bsonType: "string", maxLength: 64 },
        createdAt: { bsonType: "date" },
        expiresAt: { bsonType: "date" },
      },
    },
    indexes: [
      [{ ownerId: 1, createdAt: -1 }, { name: "ai_documents_owner" }],
      [{ storageKey: 1 }, { name: "ai_documents_storage_key", unique: true }],
      // 30 ngày, cùng hạn với bản index của nó. Đây KHÔNG phải kho lưu trữ — màn quản lý phải
      // nói rõ điều đó, nếu không người dùng sẽ coi đây là chỗ giữ tệp gốc rồi mất tệp.
      [{ expiresAt: 1 }, { name: "ai_documents_expiry", expireAfterSeconds: 0 }],
    ],
  },
];

async function apply(database) {
  const names = database.getCollectionNames();
  for (const definition of definitions) {
    const validator = { $jsonSchema: definition.schema };
    if (names.includes(definition.name)) {
      await database.runCommand({ collMod: definition.name, validator, validationLevel: "strict" });
    } else {
      await database.createCollection(definition.name, { validator, validationLevel: "strict" });
    }
    for (const [keys, options] of definition.indexes) {
      await database.getCollection(definition.name).createIndex(keys, options);
    }
  }
  return "ai_documents";
}
if (typeof module !== "undefined") module.exports = { definitions, apply };
