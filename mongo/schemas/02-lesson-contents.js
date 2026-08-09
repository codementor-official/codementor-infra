// lesson_contents — the authored body of a lesson.
//
// From data/lesson-content.ts: summary, objectives[], sections[{heading, paragraphs[]}],
// an optional code block, and an exerciseBrief[]. Sections are an open-ended, nestable,
// per-lesson structure that changes as the content team adds block types (callouts, videos,
// embeds). That is a document, not a set of tables.
//
// NOTE this fixes a real frontend bug: lesson-content.ts keys bodies by lesson TITLE, which
// already collides ("Java Core" is both a course and a shallow-course title). Here the key is
// the postgres lessons.id.

const COLLECTION = "lesson_contents";

const block = {
  bsonType: "object",
  required: ["type"],
  additionalProperties: false,
  properties: {
    type: { enum: ["paragraph", "code", "callout", "image", "video", "list"] },
    text: { bsonType: "string" },
    // code
    language: { bsonType: "string" },
    label: { bsonType: "string" },
    value: { bsonType: "string" },
    // callout
    tone: { enum: ["info", "warning", "tip"] },
    // image / video
    url: { bsonType: "string" },
    caption: { bsonType: "string" },
    durationSeconds: { bsonType: "int", minimum: 0 },
    // list
    items: { bsonType: "array", items: { bsonType: "string" } },
  },
};

const schema = {
  bsonType: "object",
  required: ["lessonId", "updatedAt"],
  additionalProperties: false,
  properties: {
    _id: { bsonType: "objectId" },
    lessonId: { bsonType: "string", description: "postgres lessons.id (uuid)" },

    summary: { bsonType: "string" },
    objectives: { bsonType: "array", items: { bsonType: "string" } },

    sections: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["heading"],
        additionalProperties: false,
        properties: {
          heading: { bsonType: "string" },
          blocks: { bsonType: "array", items: block },
        },
      },
    },

    // "Bài tập" lessons show a short brief before opening the workspace.
    exerciseBrief: { bsonType: "array", items: { bsonType: "string" } },

    // Video lessons: the asset the player streams.
    media: {
      bsonType: "object",
      additionalProperties: false,
      properties: {
        provider: { enum: ["upload", "youtube", "vimeo"] },
        url: { bsonType: "string" },
        durationSeconds: { bsonType: "int", minimum: 0 },
        captionsUrl: { bsonType: "string" },
      },
    },

    updatedAt: { bsonType: "date" },
    createdAt: { bsonType: "date" },
  },
};

function apply(db) {
  const names = db.getCollectionNames();
  if (!names.includes(COLLECTION)) {
    db.createCollection(COLLECTION, { validator: { $jsonSchema: schema }, validationLevel: "strict" });
  } else {
    db.runCommand({ collMod: COLLECTION, validator: { $jsonSchema: schema }, validationLevel: "strict" });
  }
  const c = db.getCollection(COLLECTION);
  c.createIndex({ lessonId: 1 }, { unique: true, name: "uq_lesson_id" });
  c.createIndex({ updatedAt: -1 }, { name: "ix_updated_at" });
  return COLLECTION;
}

if (typeof module !== "undefined") module.exports = { COLLECTION, schema, apply };
