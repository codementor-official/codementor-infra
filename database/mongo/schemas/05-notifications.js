// notifications — one document per announcement, NOT one per recipient.
//
// Every notification in this phase is a broadcast (`audienceType: "ALL"`), so fanning out a
// row per user would turn one published course into 10.000 near-identical documents that all
// say the same sentence. Read state is what actually differs per person, and that lives in
// `notification_reads`.
//
// The text is stored, not derived at read time. A notification is a record of what the system
// said at a moment: renaming a course afterwards must not silently rewrite the message the
// learner already saw. That also keeps the read path a plain find with no joins.

const COLLECTION = "notifications";

const schema = {
  bsonType: "object",
  required: ["eventId", "type", "title", "message", "audienceType", "createdAt"],
  additionalProperties: false,
  properties: {
    _id: { bsonType: "objectId" },

    // The Kafka envelope's eventId. Unique, and that uniqueness is the last line of defence
    // for idempotency: libs/messaging already skips duplicates via postgres `processed_events`,
    // but that table is keyed by consumer name — rename the consumer group and every past event
    // looks new again. This index makes the duplicate physically impossible to insert.
    eventId: { bsonType: "string", description: "EventEnvelope.eventId (uuid)" },

    type: {
      enum: [
        "COURSE_PUBLISHED",
        "EXERCISE_PUBLISHED",
        "ROADMAP_PUBLISHED",
        "ARTICLE_PUBLISHED",
        "ADMIN_ANNOUNCEMENT",
      ],
    },

    title: { bsonType: "string" },
    message: { bsonType: "string" },

    // Only ALL exists today. Kept as an enum rather than assumed, so adding USER/ROLE/COURSE
    // later is a validator change and not a schema redesign — the read path already filters on it.
    audienceType: { enum: ["ALL"] },

    // What the notification points at. Null for admin announcements, which reference nothing.
    referenceType: { enum: ["COURSE", "EXERCISE", "ROADMAP", "POST", null] },
    referenceId: { bsonType: ["string", "null"] },

    // The call to action, resolved when the notification is built. Storing the URL rather than
    // rebuilding it in the client keeps routing rules in one place on the server.
    actionLabel: { bsonType: ["string", "null"] },
    actionUrl: { bsonType: ["string", "null"] },

    // Free-form extras used by the copy (lecturer name, ...). Deliberately unconstrained:
    // this is the escape hatch that stops every new notification type from needing a migration.
    metadata: { bsonType: "object" },

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
  c.createIndex({ eventId: 1 }, { unique: true, name: "uq_event_id" });
  // The only read pattern: newest first, paginated.
  c.createIndex({ createdAt: -1 }, { name: "ix_created_at_desc" });
  return COLLECTION;
}

if (typeof module !== "undefined") module.exports = { COLLECTION, schema, apply };
