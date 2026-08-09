// exercise_contents — the authored body of an exercise.
//
// Why this is a document and not a table: the shape varies by exercise kind and by language.
// A code exercise carries per-language starter/solution pairs and a weighted test-case array;
// a theory exercise carries HTML and objectives; a quiz carries choices. Modelling that
// relationally means either a wide sparse table or ~6 join tables that are only ever read
// together, as one blob, by one screen (the solve workspace).
//
// What is deliberately NOT here: identity, difficulty, status, authorship, XP, dependencies.
// Those live in postgres `exercises` because they need foreign keys and cycle checks.
// See docs/04-design-decisions.md §1.

const COLLECTION = "exercise_contents";

const schema = {
  bsonType: "object",
  required: ["exerciseId", "kind", "updatedAt"],
  additionalProperties: false,
  properties: {
    _id: { bsonType: "objectId" },

    // The postgres exercises.id this body belongs to. 1:1, and the only cross-store link.
    exerciseId: { bsonType: "string", description: "postgres exercises.id (uuid)" },
    kind: { enum: ["code", "theory", "quiz"] },

    // ---- shared -------------------------------------------------------
    statement: { bsonType: "string", description: "markdown problem statement" },
    constraints: { bsonType: "array", items: { bsonType: "string" } },
    hints: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["order", "text"],
        additionalProperties: false,
        properties: {
          order: { bsonType: "int", minimum: 1 },
          text: { bsonType: "string" },
          // Hints are progressive: revealing one may cost XP.
          xpPenalty: { bsonType: "int", minimum: 0 },
        },
      },
    },

    // ---- code exercises ----------------------------------------------
    examples: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["input", "output"],
        additionalProperties: false,
        properties: {
          input: { bsonType: "string" },
          output: { bsonType: "string" },
          explanation: { bsonType: "string" },
        },
      },
    },
    testCases: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["order", "input", "expected", "visibility"],
        additionalProperties: false,
        properties: {
          order: { bsonType: "int", minimum: 1 },
          input: { bsonType: "string" },
          expected: { bsonType: "string" },
          // public cases are shown in the workspace; hidden ones only run at submit.
          visibility: { enum: ["public", "hidden"] },
          // true when produced by running the reference solution, false when hand-typed —
          // the distinction the authoring UI already tracks (ProblemTestCase.generated).
          generated: { bsonType: "bool" },
          weight: { bsonType: "int", minimum: 0 },
        },
      },
    },
    languages: {
      bsonType: "array",
      description: "per-language config; starter/solution were Record<string,string> in the frontend",
      items: {
        bsonType: "object",
        required: ["id", "label"],
        additionalProperties: false,
        properties: {
          id: { bsonType: "string" },       // "python", "cpp"
          label: { bsonType: "string" },    // "Python 3.11"
          monaco: { bsonType: "string" },   // Monaco language id
          starterCode: { bsonType: "string" },
          referenceSolution: { bsonType: "string" },
        },
      },
    },
    evaluation: {
      bsonType: "object",
      additionalProperties: false,
      properties: {
        checker: { enum: ["exact", "trimmed", "float", "custom"] },
        floatTolerance: { bsonType: "double" },
        customCheckerCode: { bsonType: "string" },
        stopOnFirstFailure: { bsonType: "bool" },
      },
    },

    // ---- theory lessons (AuthoredTheoryLesson) ------------------------
    theory: {
      bsonType: "object",
      additionalProperties: false,
      properties: {
        summary: { bsonType: "string" },
        objectives: { bsonType: "array", items: { bsonType: "string" } },
        contentHtml: { bsonType: "string" },   // Tiptap output
      },
    },

    // ---- quiz ---------------------------------------------------------
    quiz: {
      bsonType: "object",
      additionalProperties: false,
      properties: {
        questions: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["prompt", "choices"],
            additionalProperties: false,
            properties: {
              prompt: { bsonType: "string" },
              multiple: { bsonType: "bool" },
              choices: {
                bsonType: "array",
                items: {
                  bsonType: "object",
                  required: ["text", "correct"],
                  additionalProperties: false,
                  properties: {
                    text: { bsonType: "string" },
                    correct: { bsonType: "bool" },
                    explanation: { bsonType: "string" },
                  },
                },
              },
            },
          },
        },
      },
    },

    // ---- group-authored teaching metadata (GroupExercise) -------------
    teaching: {
      bsonType: "object",
      additionalProperties: false,
      properties: {
        objective: { bsonType: "string" },
        criteria: { bsonType: "string" },
        creatorNote: { bsonType: "string" },
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
  // 1:1 with postgres exercises — the join key, and the uniqueness guarantee for it.
  c.createIndex({ exerciseId: 1 }, { unique: true, name: "uq_exercise_id" });
  c.createIndex({ kind: 1 }, { name: "ix_kind" });
  // Free-text search over the statement, for the authoring bank's search box.
  c.createIndex({ statement: "text" }, { name: "txt_statement", default_language: "none" });
  c.createIndex({ updatedAt: -1 }, { name: "ix_updated_at" });
  return COLLECTION;
}

if (typeof module !== "undefined") module.exports = { COLLECTION, schema, apply };
