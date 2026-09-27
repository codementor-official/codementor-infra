// Một dòng cho mỗi lời gọi model (và mỗi lần chặn hạn mức / run hỏng) của ai-service.
// Owned by ai-service (Python, `app/telemetry.py`). Also consumed by
// codementor-backend/scripts/migrate-ai.mjs. Nguồn số liệu của trang Vận hành AI bên admin.
//
// KHÔNG chứa prompt, câu hỏi hay nội dung tài liệu: `errorMessage` chỉ là mô tả ngắn của lỗi phía
// nhà cung cấp, cắt ở 300 ký tự. Giữ 90 ngày rồi Mongo tự xoá.
const definitions = [
  {
    name: "ai_call_events",
    schema: {
      bsonType: "object",
      required: ["_id", "at", "agent", "ok"],
      properties: {
        _id: { bsonType: "objectId" },
        at: { bsonType: "date" },
        // Bề mặt gây ra lời gọi. `rag_index` là worker cắt đoạn + embedding tài liệu.
        agent: {
          bsonType: "string",
          enum: ["codey", "lecter", "lecter_workspace", "rag", "rag_index", "suggest", "dashboard"],
        },
        // `null` với sự kiện không phải lời gọi model: chặn hạn mức, run agent hỏng.
        model: { bsonType: ["string", "null"], maxLength: 100 },
        inputTokens: { bsonType: ["int", "long"], minimum: 0 },
        outputTokens: { bsonType: ["int", "long"], minimum: 0 },
        latencyMs: { bsonType: ["int", "long"], minimum: 0 },
        ok: { bsonType: "bool" },
        // `daily_limit` | `run_failed` | tên lớp lỗi của OpenAI SDK (`RateLimitError`, ...).
        errorType: { bsonType: "string", maxLength: 60 },
        errorMessage: { bsonType: "string", maxLength: 300 },
        userId: { bsonType: "string", maxLength: 64 },
        workspaceId: { bsonType: "string", maxLength: 64 },
        threadId: { bsonType: "string", maxLength: 128 },
      },
    },
    indexes: [
      [{ agent: 1, at: -1 }, { name: "ai_call_events_agent_time" }],
      [{ at: 1 }, { name: "ai_call_events_expiry", expireAfterSeconds: 90 * 24 * 60 * 60 }],
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
  return "ai_call_events";
}
if (typeof module !== "undefined") module.exports = { definitions, apply };
