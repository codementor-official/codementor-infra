// article_contents — body of an editorial article (data/articles.ts sections[]).
// Spine (slug, title, author, tag, status, publishedAt) stays in postgres `articles`.

const COLLECTION = "article_contents";

const schema = {
  bsonType: "object",
  required: ["articleId", "updatedAt"],
  additionalProperties: false,
  properties: {
    _id: { bsonType: "objectId" },
    articleId: { bsonType: "string", description: "postgres articles.id (uuid)" },
    sections: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["heading"],
        additionalProperties: false,
        properties: {
          heading: { bsonType: "string" },
          paragraphs: { bsonType: "array", items: { bsonType: "string" } },
          code: { bsonType: "string" },
          language: { bsonType: "string" },
        },
      },
    },
    // HTML from the WYSIWYG editor, exactly as lesson_contents.contentHtml does it.
    // `sections` above models prose as typed blocks — the right shape for content built
    // by a pipeline, but it cannot round-trip what an editor produces without losing
    // formatting in both directions. The two coexist: blocks for structured imports,
    // `contentHtml` for anything a person actually writes.
    //
    // The collection validates strictly with additionalProperties:false, so without this
    // the editor's first save is rejected by the database.
    contentHtml: { bsonType: "string" },

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
  c.createIndex({ articleId: 1 }, { unique: true, name: "uq_article_id" });
  return COLLECTION;
}

if (typeof module !== "undefined") module.exports = { COLLECTION, schema, apply };
