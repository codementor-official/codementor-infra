// Owned by ai-service (Python). No PostgreSQL tables or external vector database.
// This definition is also consumed by codementor-backend/scripts/migrate-ai.mjs.
const definitions = [
  {
    name: "ai_document_indexes",
    schema: {
      bsonType: "object",
      required: ["_id", "workspaceId", "documentId", "model", "source", "state", "chunks", "updatedAt", "leaseUntil"],
      properties: {
        _id: { bsonType: "string" }, workspaceId: { bsonType: "string" }, documentId: { bsonType: "string" },
        model: { bsonType: "string" }, source: { bsonType: "object" },
        state: { enum: ["queued", "processing", "ready", "failed"] },
        chunks: { bsonType: "array", maxItems: 160, items: {
          bsonType: "object", required: ["text", "page", "embedding"],
          properties: {
            text: { bsonType: "string" }, page: { bsonType: ["int", "long", "null"] },
            embedding: { bsonType: "array", minItems: 1536, maxItems: 1536, items: { bsonType: ["double", "int", "long"] } },
          },
        } },
        chunkCount: { bsonType: ["int", "long"] }, updatedAt: { bsonType: "date" },
        leaseUntil: { bsonType: "date" }, leaseId: { bsonType: "string" }, error: { bsonType: "string" },
        expiresAt: { bsonType: "date" },
      },
    },
    indexes: [
      [{ model: 1, state: 1, updatedAt: 1 }, { name: "ai_index_queue" }],
      [{ workspaceId: 1, documentId: 1 }, { name: "ai_index_workspace_document" }],
      [{ expiresAt: 1 }, { name: "ai_index_expiry", expireAfterSeconds: 0 }],
    ],
  },
  {
    name: "ai_conversations",
    schema: {
      bsonType: "object",
      required: ["_id", "userId", "workspaceId", "title", "sources", "turns", "createdAt", "updatedAt", "leaseUntil"],
      properties: {
        _id: { bsonType: "string" }, userId: { bsonType: "string" }, workspaceId: { bsonType: "string" },
        title: { bsonType: "string", maxLength: 100 }, sources: { bsonType: "array", minItems: 1, maxItems: 8 },
        turns: { bsonType: "array", maxItems: 50, items: {
          bsonType: "object", required: ["id", "question", "answer", "citations", "insufficientEvidence", "createdAt"],
          properties: {
            id: { bsonType: "string" }, question: { bsonType: "string", maxLength: 4000 },
            answer: { bsonType: "string" }, citations: { bsonType: "array", maxItems: 8 },
            supplementalAnswer: { bsonType: "string" },
            insufficientEvidence: { bsonType: "bool" }, createdAt: { bsonType: "string" },
          },
        } },
        createdAt: { bsonType: "date" }, updatedAt: { bsonType: "date" }, leaseUntil: { bsonType: "date" }, leaseId: { bsonType: "string" },
      },
    },
    indexes: [[{ userId: 1, workspaceId: 1, updatedAt: -1, _id: -1 }, { name: "ai_conversation_history" }]],
  },
  {
    name: "ai_usage",
    schema: {
      bsonType: "object", required: ["_id", "count", "expiresAt"],
      properties: { _id: { bsonType: "string" }, count: { bsonType: ["int", "long"] }, expiresAt: { bsonType: "date" } },
    },
    indexes: [[{ expiresAt: 1 }, { name: "ai_usage_expiry", expireAfterSeconds: 0 }]],
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
  return "ai_conversations";
}
if (typeof module !== "undefined") module.exports = { definitions, apply };
