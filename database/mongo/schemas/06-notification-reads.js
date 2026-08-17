// notification_reads — which user has read which notification.
//
// Split from `notifications` on purpose: the announcement is shared by everyone, the read
// state is personal. Keeping them in one document would mean either a per-user copy of the
// text, or an ever-growing `readBy` array inside a hot document — the classic unbounded-array
// mistake, where the document eventually exceeds 16MB and every read drags the whole list.
//
// A row exists ONLY once a user has read something. Unread is the absence of a row, so a new
// notification costs nothing per user until someone actually opens it.

const COLLECTION = "notification_reads";

const schema = {
  bsonType: "object",
  required: ["notificationId", "userId", "readAt"],
  additionalProperties: false,
  properties: {
    _id: { bsonType: "objectId" },
    notificationId: { bsonType: "objectId", description: "notifications._id" },
    userId: { bsonType: "string", description: "postgres users.id (uuid)" },
    readAt: { bsonType: "date" },
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
  // Marking the same notification read twice must be a no-op, not a second row: the client
  // fires this on click and clicks repeat. Unique lets the write be an idempotent upsert.
  c.createIndex({ userId: 1, notificationId: 1 }, { unique: true, name: "uq_user_notification" });
  return COLLECTION;
}

if (typeof module !== "undefined") module.exports = { COLLECTION, schema, apply };
