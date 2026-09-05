// Lịch sử hội thoại của agent (Lecter, và sau này Codey). Owned by ai-service (Python).
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
        _id: { bsonType: "string", maxLength: 128 },
        userId: { bsonType: "string" },
        agentId: { bsonType: "string", enum: ["lecter", "codey"] },
        title: { bsonType: "string", maxLength: 120 },
        messages: { bsonType: "array", maxItems: 400, items: { bsonType: "object" } },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" },
        expiresAt: { bsonType: "date" },
      },
    },
    indexes: [
      [{ userId: 1, agentId: 1, updatedAt: -1 }, { name: "ai_agent_session_history" }],
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
