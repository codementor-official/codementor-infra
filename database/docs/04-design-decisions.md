# Design Decisions & Trade-offs

The choices worth defending, and what each one costs.

## 1. Exercises are split: relational spine in PostgreSQL, body in MongoDB

**Decision.** `exercises` (identity, slug, difficulty, status, XP, limits, author, cached counts)
is a PostgreSQL table. The authored content (statement, test cases, hints, per-language starter
code, evaluation config) is a MongoDB document joined by `exercises.content_ref`.

**Why not fully in MongoDB**, as a literal reading of the brief would suggest: five things point
at an exercise and every one of them needs referential integrity —

```
exercise_set_items       set membership, with position
exercise_progress        per-user state, cascade on user delete
submissions              grading records, ON DELETE RESTRICT
lessons.exercise_id      a lesson of type='exercise' runs one
```

(`exercise_prerequisites` used to belong on this list too — removed in `0021`, see §3/§5 below.)

With the exercise living only in Mongo, all five become unenforced string references. Deleting an
exercise would silently orphan submissions; a prerequisite could point at a document that no
longer exists; the cycle trigger could not run at all. The brief simultaneously requires
*"Preserve referential integrity"* and *"the database/domain layer must enforce integrity wherever
possible"* — those requirements decide it.

**Cost.** Two writes to publish an exercise, and a possible orphan document if the second fails.
Mitigated by ordering (document first, then `content_ref`) and by the
`CHECK (status <> 'published' OR content_ref IS NOT NULL)` constraint. The orphan is inert
because all reads start from PostgreSQL.

## 2. Content and per-user state are separated

The frontend stores `isCompleted`, `isLocked`, `progressPercent`, `status` and `isFavorite` **on
the shared content record**. That works for one mock user and is a data-corruption bug for two.
Everything per-learner moved to `lesson_progress`, `exercise_progress`, `course_enrollments` and
`roadmap_enrollments`, keyed by `(user_id, entity_id)`.

`isLocked` did not move — it was **deleted**. It cannot be stored at all: availability depends on
the asking learner and on the progression mode, so it is computed by `fn_lesson_available()`.

## 3. AND/OR as `group_index` (DNF) rather than an expression tree

> **Update (`0021`):** this decision applies to `lesson_prerequisites` only now.
> `roadmap_course_prerequisites`, `course_prerequisites`, `chapter_prerequisites` and
> `exercise_prerequisites` were dropped — no application code ever wrote edges into them, so the
> AND/OR evaluation they existed for never ran outside this repo's own seed/verify data. See
> `02-dependency-model.md`.

**Decision.** One `smallint` per edge. Same group = AND, different groups = OR.

**Alternative rejected:** a node table (`AND`/`OR`/`LEAF` with parent pointers) giving arbitrary
nesting. It triples query complexity — availability becomes a recursive evaluation instead of one
`GROUP BY … HAVING bool_and(...)` — to buy expressiveness no screen has ever asked for.

**Cost.** `(A OR B) AND C` must be expanded to two groups: `(A,0),(C,0),(B,1),(C,1)`. Acceptable:
the product's real cases are "one prerequisite", "two prerequisites", and occasionally "either of
two". If a tree is ever genuinely needed, the flat rows convert into one mechanically — nothing
is lost.

**Rejected non-option:** a `logic` column (`'all' | 'any'`) on the *target*. It cannot express
`(A AND B) OR C` at all, and quietly forces every prerequisite set into one uniform mode.

## 4. `linear` mode gates on `position`; `graph` mode gates on edges

These are different rules, not one rule with different data:

- `graph` evaluates prerequisite edges. Branching, AND, OR.
- `linear` ignores edges entirely and requires every earlier non-optional sibling to be complete.
- `free` opens everything.

**Why it matters.** A strictly sequential 30-lesson course needs **zero** edge rows under
`linear`; expressing the same thing as a graph would need 29 rows that all say the same thing and
must be rewritten whenever a lesson is inserted. This keeps ordering and dependency genuinely
separate rather than making one impersonate the other.

## 5. Prerequisites exist at two course levels — historical, both removed in `0021`

Neither table survived: no usecase or DTO ever wrote to either one, so the distinction below never
got exercised outside seed data. Kept as a record of the reasoning in case a future "course needs
course, regardless of curriculum" requirement brings one of them back.

`course_prerequisites` (intrinsic) and `roadmap_course_prerequisites` (curricular) looked redundant
but answered different questions:

| | Question | Example |
| --- | --- | --- |
| `course_prerequisites` | what must be true to *understand* this course | Spring Boot REST API needs Java Core, in any context |
| `roadmap_course_prerequisites` | what this *curriculum* wants you to do first | this roadmap teaches SQL before Spring, another does not |

Edges in the second referenced `roadmap_courses.id` (the membership row), so the same course could
be gated in one roadmap and free in another without duplicating the course.

## 6. Scope violations are prevented by composite FKs, not triggers

A cross-course lesson dependency is rejected by carrying `course_id` on the edge row and pointing
a composite foreign key at `lessons(course_id, id)`. Same technique for chapters, roadmap courses,
exercise sets, and group assignments.

This required denormalising `lessons.course_id` — which is safe because a second composite FK
(`(course_id, chapter_id) → chapters(course_id, id)`) makes it *provably* equal to the chapter's
course. The denormalised column cannot drift.

**Why not triggers.** Declarative constraints cannot be bypassed by a bulk load, a migration, or
an admin script, and cost nothing at runtime. Only cycle detection genuinely needs procedural code
today — the archived-content check (`fn_reject_archived_*_edge`) went with the three tables it
guarded in `0021`.

## 7. Progress: persisted, derived, or cached

| Level | Treatment | Reasoning |
| --- | --- | --- |
| Lesson, exercise | **Persisted** | irreducible learner facts |
| Chapter | **Derived** | one `count(...)` over lessons already in memory; no screen sorts by it |
| Course, roadmap | **Cached** on the enrolment row | read on every card of every grid; recomputing per card is O(cards × lessons) |

The caches are maintained by triggers on `lesson_progress`, never written by the application, and
their invariant is re-derived from scratch by `postgres/verify.sql` — so drift is a test failure,
not a support ticket.

**Cost.** Every lesson completion writes to the enrolment row and possibly a roadmap row. That is
one extra write on an action a learner takes a few times an hour; the alternative is an aggregate
on every page render.

**"Completed" is defined once per level** (`01-domain-model.md §3.1`) rather than being left to
each caller — lesson = marked complete, exercise = accepted submission, chapter/course = all
non-optional children complete.

## 8. Cycle prevention

A `BEFORE INSERT OR UPDATE` trigger walks forward from the new edge's target and fails if the
source is reachable — catching indirect cycles (`A→B→C→A`), not just `A↔B`. It uses `UNION`, so
pre-existing bad data cannot make the probe loop forever, and it is scoped to one course/set, so
the traversal stays small.

One generic function (`fn_prevent_dependency_cycle`), parameterised with table and column names
via `TG_ARGV`, originally served all five prerequisite tables so the rule couldn't diverge between
levels. Four of those tables are gone (`0021`); the function itself was kept and still guards
`lesson_prerequisites`, the one level that ended up wired to the application.

Verified: `postgres/verify.sql` asserts direct and indirect cycles are both rejected with
SQLSTATE `23514`.

## 9. Enum arrays instead of JSON for learner preferences

`interested_fields roadmap_field[]` and `preferred_learning_styles learning_style[]` are native
typed arrays with a GIN index — constrained by the enum, queryable with `&&`, and not a JSON blob.
`weeklyStudySchedule` became a **table** (`study_schedule_slots`) rather than either, because the
reminder scheduler must ask *"who has a session at 19:00 on Monday"* across all users, which a
per-user blob cannot answer without a full scan.

## 10. Two independent moderation axes on documents

`group_documents.status` (human: published/pending/changes/rejected/hidden) and `ai_verdict`
(automated pre-screen: valid/warning/invalid) are kept separate because they genuinely disagree —
the frontend's `DocumentVerdict` comment says anything but `valid` *needs* a human decision.
Collapsing them into one column would destroy the distinction between "AI flagged it" and "a
moderator rejected it".

## 11. What was deliberately left out

| Not built | Why |
| --- | --- |
| Application/business logic | explicitly out of scope for this phase |
| Notifications, AI-tutor transcripts, admin audit log | present in the frontend only as placeholder screens with no data shape to model |
| Soft-delete columns everywhere | `status` enums already cover retirement; a second mechanism invites disagreement |
| Partitioning on `submissions` | correct eventually, premature now; the index layout will not have to change when it happens |
| Full-text search infrastructure | one `tsvector`/text index is enough at this size; a search service is a later decision |
| `is_daily` exercise flag | the frontend's "bài tập hôm nay" is a scheduling concern, better served by an `exercise_sets` row of kind `daily` than a boolean that needs resetting |

## 12. Extension points

- **New content type** (e.g. live workshops): add a table + its own `*_prerequisites` and reuse
  `fn_prevent_dependency_cycle` by passing new column names — no new logic.
- **Richer dependency logic:** DNF rows convert to an expression tree without data loss.
- **Weighted progress** (lessons worth different amounts): add `weight` to `lessons` and change
  two aggregate expressions in `0012_progress_triggers.sql`; no schema reshape.
- **Multi-tenant / cohorts:** `study_groups` already carries the membership and permission model
  an institution would need.
