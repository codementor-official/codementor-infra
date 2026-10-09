// Lịch sử hội thoại của agent (Lecter, Codey, Tutor). Owned by ai-service (Python).
// This definition is also consumed by codementor-backend/scripts/migrate-ai.mjs.
//
// Tách khỏi `ai_conversations` (07) có chủ đích: validator ở đó bắt mọi turn phải mang
// `citations` + `insufficientEvidence` — bằng chứng trích dẫn của RAG, thứ hội thoại agent không
// có — và chặn ở 50 turn. Nhét hội thoại agent vào đó là bị Mongo từ chối lúc ghi.
//
// `messages` cố tình để lỏng ở mức phần tử: nó lưu nguyên dạng Message của giao thức AG-UI, và
// hình dạng đó do thư viện quyết định (assistant có `toolCalls`, tool có `toolCallId`, content có
// thể null). Siết nó ở đây nghĩa là mỗi lần thư viện thêm một trường thì mọi lượt chat đều gãy ở
// bước lưu — đúng cái bẫy khiến `ai_conversations` không tái dùng được.
const definitions = [
  {
    name: "ai_agent_sessions",
    schema: {
      bsonType: "object",
      required: ["_id", "userId", "agentId", "title", "messages", "createdAt", "updatedAt"],
      properties: {
        // `${agentId}:${threadId}` — threadId do trình duyệt sinh, agentId nằm trong khoá để hai
        // agent không đụng nhau nếu cùng một threadId được dùng lại.
        // `${agentId}:${threadId}`, hoặc `${agentId}:${workspaceId}:${threadId}` với bề mặt
        // nhóm học: một người ở hai nhóm phải thấy hai danh sách rời nhau, và cùng một
        // `threadId` ở hai nhóm không được trỏ về một bản ghi.
        _id: { bsonType: "string", maxLength: 128 },
        userId: { bsonType: "string" },
        agentId: { bsonType: "string", enum: ["lecter", "lecter_workspace", "codey", "tutor"] },
        // Chỉ có ở bề mặt nhóm học. Đi cùng `userId` trong mọi truy vấn — bỏ một trong hai là
        // hội thoại của nhóm khác lọt vào danh sách.
        workspaceId: { bsonType: "string" },
        // Thread thật, tách khỏi `_id`: đọc bằng cách cắt chuỗi thì thêm một đoạn khoá là hỏng.
        threadId: { bsonType: "string" },
        title: { bsonType: "string", maxLength: 120 },
        messages: { bsonType: "array", maxItems: 400, items: { bsonType: "object" } },
        // Chỉ Tutor ghi. Khoá là id tin nhắn của NGƯỜI DÙNG (trình duyệt sinh, ổn định qua mọi
        // lần phát lại), giá trị là lượt đã đối chiếu trích dẫn — cùng hình dạng một turn của
        // `ai_conversations` cũ, nên script migrate chép thẳng sang. Server là nguồn sự thật:
        // endpoint đọc lại trường này từ đây, không tin bản trình duyệt gửi lên.
        grounding: { bsonType: "object" },
        // Tài liệu đang chọn ở lượt gần nhất `[{id, title}]` — chỉ để mở lại hội thoại đúng
        // lựa chọn cũ. Quyền đọc vẫn kiểm lại ở mỗi lượt.
        documents: { bsonType: "array", maxItems: 8, items: { bsonType: "object" } },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" },
        expiresAt: { bsonType: "date" },
      },
    },
    indexes: [
      [{ userId: 1, agentId: 1, updatedAt: -1 }, { name: "ai_agent_session_history" }],
      [
        { userId: 1, agentId: 1, workspaceId: 1, updatedAt: -1 },
        { name: "ai_agent_session_workspace_history" },
      ],
      // 90 ngày: đây là thứ người dùng quay lại đọc, không phải cache như `ai_document_indexes`
      // (30 ngày) — nhưng vẫn có hạn để hội thoại bỏ quên không nằm lại vô thời hạn.
      [{ expiresAt: 1 }, { name: "ai_agent_session_expiry", expireAfterSeconds: 0 }],
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
  return "ai_agent_sessions";
}
if (typeof module !== "undefined") module.exports = { definitions, apply };
