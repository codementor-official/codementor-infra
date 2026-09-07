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
        // Vòng duyệt nội dung. Khác năm loại trên ở chỗ người nhận không phải người học:
        // REVIEW_REQUESTED gửi cho admin, các loại còn lại gửi riêng cho tác giả.
        "CONTENT_REVIEW_REQUESTED",
        // Tác giả xin gỡ một nội dung ĐANG công khai. Cũng gửi cho admin, nhưng ngược
        // chiều REVIEW_REQUESTED: kia xin đưa lên, đây xin gỡ xuống, và đây luôn kèm lý do.
        "CONTENT_REMOVAL_REQUESTED",
        "CONTENT_APPROVED",
        "CONTENT_CHANGES_REQUESTED",
        "CONTENT_REJECTED",
        // Admin thu hồi nội dung đang công khai — kể cả khi đó là duyệt một yêu cầu XIN GỠ
        // mà chính tác giả vừa gửi (`requestRemoval`). Gỡ mà không báo thì tác giả chỉ phát
        // hiện qua việc trang của mình biến mất.
        "CONTENT_ARCHIVED",
        // Admin từ chối một yêu cầu xin gỡ — nội dung vẫn công khai như cũ, tác giả cần biết
        // để không tưởng nhầm là nó đã được gỡ.
        "REMOVAL_REQUEST_DENIED",
        "WORKSPACE_JOIN_APPROVED",
        "WORKSPACE_JOIN_REJECTED",
        "WORKSPACE_ASSIGNMENT_CREATED",
        "WORKSPACE_ASSIGNMENT_DUE_SOON",
        "WORKSPACE_ASSIGNMENT_OVERDUE",
        "WORKSPACE_MESSAGE",
        "WORKSPACE_ASSIGNMENT_RETRY",
        "WORKSPACE_DEADLINE_CHANGED",
        "WORKSPACE_MEMBER_ADDED",
        "LEARNING_REMINDER",
        "WORKSPACE_DOCUMENT_PENDING",
        "WORKSPACE_DOCUMENT_PUBLISHED",
        "WORKSPACE_DOCUMENT_REJECTED",
        "WORKSPACE_EXERCISE_UPDATED",
        "WORKSPACE_JOIN_REQUESTED",
        "WORKSPACE_MEMBER_JOINED",
        "WORKSPACE_MEMBER_LEFT",
        "WORKSPACE_MEMBER_ROLE_CHANGED",
        "WORKSPACE_ASSIGNMENT_REVIEWED",
        "STUDY_SESSION_REMINDER",
        "COURSE_COMPLETED",
      ],
    },

    title: { bsonType: "string" },
    message: { bsonType: "string" },

    // Who the notification is for. ALL is every signed-in user; ROLE and USER narrow it to
    // one role or one person, and `audienceKey` carries which.
    audienceType: { enum: ["ALL", "ROLE", "USER"] },

    // Role name for ROLE, Keycloak `sub` for USER, null for ALL. Keycloak's subject rather
    // than `users.id` because realtime-service keys its socket rooms off the handshake token
    // and deliberately never reads another service's tables.
    //
    // Not in `required`: documents written before targeting existed have no such field, and
    // making it required would reject the next write that touches one of them.
    audienceKey: { bsonType: ["string", "null"] },

    // What the notification points at. Null for admin announcements, which reference nothing.
    referenceType: { enum: ["COURSE", "EXERCISE", "ROADMAP", "POST", "WORKSPACE", null] },
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
  // The only read pattern: newest first, paginated, filtered to what this viewer is
  // addressed by. Audience first because it is the selective part — leading with createdAt
  // makes the index a full scan in date order once most notifications are not for you.
  c.createIndex(
    { audienceType: 1, audienceKey: 1, createdAt: -1 },
    { name: "ix_audience_created_at_desc" },
  );
  return COLLECTION;
}

if (typeof module !== "undefined") module.exports = { COLLECTION, schema, apply };
