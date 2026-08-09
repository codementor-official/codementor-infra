# MongoDB Model

Four collections. Each has a single, stated domain responsibility; nothing is here merely
because it is convenient to store loosely.

| Collection | Owns | Links to PostgreSQL via | Cardinality |
| --- | --- | --- | --- |
| `exercise_contents` | authored body of an exercise | `exerciseId` → `exercises.id` | 1:1 |
| `lesson_contents` | authored body of a lesson | `lessonId` → `lessons.id` | 1:1 |
| `submission_run_details` | per-test judge output | `submissionId` → `submissions.id` | 1:1 |
| `article_contents` | body of an editorial article | `articleId` → `articles.id` | 1:1 |

The reverse pointer (`exercises.content_ref`, `lessons.content_ref`,
`submissions.run_detail_ref`, `articles.content_ref`) holds the Mongo `_id` as text, so a join
is possible in either direction without a lookup table.

## 1. Why these four and nothing else

The rule applied: **a document earns its place when its shape varies per row and the whole thing
is read at once by a single screen.** Everything failing that test stayed relational.

| Considered | Verdict | Reason |
| --- | --- | --- |
| exercise statement, test cases, per-language starter code | **Mongo** | shape varies by kind and by language; read as one blob by the solve workspace |
| lesson sections/blocks | **Mongo** | open-ended block types (paragraph, code, callout, video, list) that grow over time |
| judge per-test output | **Mongo** | bulky, append-only, runtime-specific, rarely read |
| article sections | **Mongo** | same block-structure argument as lessons |
| exercise identity, difficulty, status, XP | PostgreSQL | needs FKs from dependencies, progress, sets, assignments |
| exercise ↔ tag / technology / company | PostgreSQL | filter facets must join reliably; embedded arrays make cross-entity filtering guesswork |
| submissions (who, verdict, score) | PostgreSQL | transactional, joined constantly, grading integrity |
| users, groups, permissions, progress | PostgreSQL | the brief rules this out, and correctly |
| lesson→exercise link | PostgreSQL | a real relationship, needs `ON DELETE SET NULL` |

## 2. `exercise_contents`

Consolidates the four frontend shapes (`Problem`, `AuthoredCodeProblem`, `CodeProblemDraft`,
`GroupExercise` body) into one document.

```js
{
  _id: ObjectId("65f0…ee01"),
  exerciseId: "10000000-…-000000000001",   // postgres exercises.id
  kind: "code",                             // code | theory | quiz

  statement: "Cho mảng `a` gồm `n` số nguyên…",   // markdown
  constraints: ["1 ≤ n ≤ 10^5", "…"],
  hints: [ { order: 1, text: "Duyệt từ trái sang phải…", xpPenalty: 5 } ],

  examples: [ { input: "5\n3 7 1 9 4\n9", output: "3", explanation: "a[3] = 9" } ],

  testCases: [
    { order: 1, input: "…", expected: "3",  visibility: "public", generated: false, weight: 1 },
    { order: 3, input: "…", expected: "0",  visibility: "hidden", generated: true,  weight: 1 }
  ],

  languages: [                              // was Record<string,string> in the frontend
    { id: "python", label: "Python 3.11", monaco: "python",
      starterCode: "def solve(a, x):\n    pass\n",
      referenceSolution: "…" }
  ],

  evaluation: { checker: "trimmed", floatTolerance: 1e-6, stopOnFirstFailure: false },

  theory:   { summary, objectives: [], contentHtml },   // kind='theory'
  quiz:     { questions: [ { prompt, multiple, choices: [ { text, correct, explanation } ] } ] },
  teaching: { objective, criteria, creatorNote },       // group-authored metadata

  createdAt: ISODate(), updatedAt: ISODate()
}
```

**Embedded, not referenced** — test cases, examples, hints and language configs have no
independent identity, are never queried across exercises, and are always loaded with their
parent. Referencing them would create four collections that are only ever `$lookup`-ed back
together.

Indexes:

| Index | Purpose |
| --- | --- |
| `{exerciseId: 1}` unique | the join key; also guarantees the 1:1 |
| `{kind: 1}` | authoring bank filters by kind |
| `{statement: "text"}` | search box over problem text (`default_language: "none"` — the corpus is Vietnamese, which Mongo has no stemmer for; a language-specific stemmer would do more harm than good) |
| `{updatedAt: -1}` | "recently edited" ordering |

## 3. `lesson_contents`

```js
{
  _id: ObjectId("65f0…ff01"),
  lessonId: "f0000000-…-000000000001",
  summary: "Cấu trúc một chương trình Java…",
  objectives: ["Nhận biết class, phương thức main…"],
  sections: [
    { heading: "Một chương trình Java bắt đầu từ đâu?",
      blocks: [
        { type: "paragraph", text: "Java tổ chức mã nguồn bên trong class…" },
        { type: "code", label: "Main.java", language: "java", value: "public class Main {…}" },
        { type: "callout", tone: "tip", text: "Tên class phải trùng tên file." }
      ] }
  ],
  exerciseBrief: ["Tạo class Book…"],
  media: { provider: "upload", url: "…", durationSeconds: 840, captionsUrl: "…" },
  createdAt, updatedAt
}
```

The `blocks` array replaces the frontend's fixed `{heading, paragraphs[]}` + one optional code
field — the same content, but new block types no longer require a schema change.

**This fixes a live frontend bug:** `data/lesson-content.ts` keys bodies by lesson *title*, and
titles already collide in the catalogue. Here the key is `lessonId`, unique by construction.

Indexes: `{lessonId: 1}` unique, `{updatedAt: -1}`.

## 4. `submission_run_details`

```js
{
  _id: ObjectId(…),
  submissionId: "…",                       // postgres submissions.id
  compile: { success: true, stderr: "", durationMs: 310 },
  cases: [
    { order: 1, passed: true,  visibility: "public",
      input: "…", expected: "3", actual: "3", runtimeMs: 18, memoryKb: 14080, verdict: "accepted" },
    { order: 3, passed: false, visibility: "hidden",
      actual: "-1", verdict: "wrong_answer", runtimeMs: 12, memoryKb: 13990 }
  ],
  judge: { worker: "judge-3", imageTag: "py3.11-1.4", languageVersion: "3.11.9" },
  createdAt: ISODate()
}
```

The submission itself stays in PostgreSQL. Only this diagnostic payload — the largest and least
frequently read part — lives here, keeping the `submissions` table narrow enough to scan for
history and leaderboards.

Indexes: `{submissionId: 1}` unique, and a **TTL index on `createdAt` (180 days)** — run details
are debugging aids, not records of account. Verdict and score, which *are* records of account,
are in PostgreSQL and never expire.

## 5. `article_contents`

`{articleId, sections: [{heading, paragraphs[], code, language}], createdAt, updatedAt}`.
Index `{articleId: 1}` unique.

## 6. Validation and consistency

Every collection is created with a `$jsonSchema` validator at `validationLevel: "strict"` and
`additionalProperties: false`, so an unexpected field is rejected rather than silently stored —
the closest Mongo equivalent to the `NOT NULL`/`CHECK` discipline on the relational side.

Cross-store consistency is **not** transactional, and the schema is arranged so it does not need
to be:

- PostgreSQL is authoritative for existence. A row with `content_ref IS NULL` is simply
  unpublished — and `exercises`/`articles` carry a `CHECK` forbidding `status='published'`
  without a `content_ref`.
- An orphaned Mongo document (body written, spine rolled back) is inert: nothing can reach it,
  because every read starts from PostgreSQL.
- The dangerous direction — spine pointing at a missing body — is prevented by writing the
  document **first**, then the `content_ref`.
