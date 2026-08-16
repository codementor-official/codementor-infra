// submission_run_details — per-test-case judge output for one submission.
//
// The submission itself (who, which exercise, verdict, score, source code) is relational and
// lives in postgres `submissions`: it is transactional, it is joined constantly, and grading
// integrity depends on referential integrity.
//
// What lands here is the bulky, append-only, judge-specific part: stdout/stderr per test,
// diffs, compiler messages. Its shape changes per language runtime, it is written once and
// read rarely (only when a learner expands "chi tiết"), and it is the largest payload in the
// system. Keeping it out of postgres keeps the submissions table narrow and fast to scan.

const COLLECTION = "submission_run_details";

const schema = {
  bsonType: "object",
  required: ["submissionId", "createdAt"],
  additionalProperties: false,
  properties: {
    _id: { bsonType: "objectId" },
    submissionId: { bsonType: "string", description: "postgres submissions.id (uuid)" },

    compile: {
      bsonType: "object",
      additionalProperties: false,
      properties: {
        success: { bsonType: "bool" },
        stderr: { bsonType: "string" },
        durationMs: { bsonType: "int", minimum: 0 },
      },
    },

    cases: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["order", "passed"],
        additionalProperties: false,
        properties: {
          order: { bsonType: "int", minimum: 1 },
          passed: { bsonType: "bool" },
          visibility: { enum: ["public", "hidden"] },
          // Hidden-case input/output are omitted when serving a learner; stored for mentors.
          // Still strings in function mode: the judge writes json.dumps() of the value, so
          // this validator needs no migration and the UI keeps rendering them as text.
          input: { bsonType: "string" },
          expected: { bsonType: "string" },
          actual: { bsonType: "string" },
          stderr: { bsonType: "string" },
          runtimeMs: { bsonType: "int", minimum: 0 },
          memoryKb: { bsonType: "int", minimum: 0 },
          verdict: {
            // `skipped`: the container died (hard timeout, OOM) before this case ran. Only
            // reachable in function mode, where all cases share one container.
            enum: [
              "accepted",
              "wrong_answer",
              "runtime_error",
              "timeout",
              "memory_exceeded",
              "skipped",
            ],
          },
        },
      },
    },

    // Whatever the learner printed, captured separately from the graded result. In function
    // mode the driver owns stdout, so print() debugging has to be collected and handed back
    // rather than silently discarded — it is the console tab of the solve workspace.
    consoleOutput: { bsonType: "string" },

    judge: {
      bsonType: "object",
      additionalProperties: false,
      properties: {
        worker: { bsonType: "string" },
        imageTag: { bsonType: "string" },
        languageVersion: { bsonType: "string" },
      },
    },

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
  c.createIndex({ submissionId: 1 }, { unique: true, name: "uq_submission_id" });
  // Run details are diagnostic; they do not need to be kept forever. 180 days.
  c.createIndex({ createdAt: 1 }, { name: "ttl_created_at", expireAfterSeconds: 60 * 60 * 24 * 180 });
  return COLLECTION;
}

if (typeof module !== "undefined") module.exports = { COLLECTION, schema, apply };
