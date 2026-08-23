# Dependency Model

`0006_dependencies.sql` originally built the same AND/OR mechanism at five levels: roadmap→course,
course→course, chapter, lesson, exercise. `0021_drop_unused_prerequisite_graph.sql` removed four of
them — `roadmap_course_prerequisites`, `course_prerequisites`, `chapter_prerequisites`,
`exercise_prerequisites` and their `fn_*_available` functions never got an application writer or
caller; only this repo's own seed/verify data ever touched them. **Lesson-level gating is the only
one still live**: `learning-service` derives `lesson_prerequisites` automatically from curriculum
order (`deriveLessonSources` — always a single AND group, never OR), and `fn_lesson_available` is
the only one of the six original functions any service calls. This document now describes that one
level; the mechanism below is preserved because lesson gating still uses it.

## 1. Ordering is not dependency

Two independent columns/concepts, never conflated:

| | Stored as | Means | Affects availability? |
| --- | --- | --- | --- |
| **Order** | `position int` on the child row | where it renders in the list | **No** |
| **Dependency** | a row in `lesson_prerequisites` | what must be finished first | **Yes** |

So this is legal and meaningful:

```
position 1  Lesson "Giới thiệu"          no prerequisites   → available immediately
position 2  Lesson "Bài tập tổng hợp"    requires 3 and 4   → locked
position 3  Lesson "Cú pháp"             no prerequisites   → available immediately
position 4  Lesson "Vòng lặp"            requires 3         → locked until 3 done
```

In practice `learning-service` never authors this shape by hand — see §3.

## 2. The edge

```sql
target_lesson_id  -- the lesson being gated
source_lesson_id  -- the lesson that must be completed first
group_index        -- smallint, default 0
```

Read as: *"`target` requires `source`"*. The edge points **from prerequisite to dependent**.

### 2.1 AND / OR via `group_index` (disjunctive normal form)

```
Edges in the SAME group are ANDed.
Different groups are ORed.
```

`target` is unlocked when **at least one group is fully satisfied**. This covers every case the
product might need with one `smallint`:

| Requirement | Rows `(source, group_index)` |
| --- | --- |
| No prerequisite | *(no rows)* |
| Only A | `(A,0)` |
| A **and** B | `(A,0), (B,0)` |
| A **or** B | `(A,0), (B,1)` |

`learning-service` only ever writes the "no prerequisite" and "A and B..." shapes — order-derived
edges are always a single group. Nothing in the app writes a second `group_index` for the same
target, so the OR half of this mechanism is schema-capable but currently unreached. See
`04-design-decisions.md §3` for why DNF was chosen over an expression tree regardless.

### 2.2 Availability query

```sql
-- Is lesson L available to user U?
SELECT
  NOT EXISTS (SELECT 1 FROM lesson_prerequisites WHERE target_lesson_id = L)  -- no prereqs at all
  OR EXISTS (                                                                 -- ...or some group fully met
    SELECT 1
    FROM lesson_prerequisites lp
    WHERE lp.target_lesson_id = L
    GROUP BY lp.group_index
    HAVING bool_and(
      EXISTS (SELECT 1 FROM lesson_progress p
              WHERE p.user_id = U AND p.lesson_id = lp.source_lesson_id
                AND p.status = 'completed')
    )
  );
```

`postgres/migrations/0011_availability_functions.sql` ships this as
`fn_lesson_available(user_id, lesson_id)` — the only `fn_*_available` function left after 0021, and
the one `prisma-enrollment.repository.ts` calls.

### 2.3 Progression mode gates whether edges are enforced

Edges describe *structure*; mode decides whether that structure is **enforced** for a given learner.

| Mode | Behaviour |
| --- | --- |
| `free` | all content available; prerequisites are advisory |
| `graph` | the DNF prerequisite edges are evaluated |
| `linear` | **`position` itself is the gate**: every earlier non-optional sibling must be completed. Edges are ignored, and none need to be authored |

Resolution order for a learner: `enrollment.mode_override` → falls back to the container's
`progression_mode`.

`progression_mode` is still a column on `roadmaps`, `courses`, `chapters` (via the course) and
`exercise_sets` — the enum itself wasn't touched by 0021. But since `roadmap_course_prerequisites`,
`course_prerequisites`, `chapter_prerequisites` and `exercise_prerequisites` no longer exist, setting
`'graph'` at any of those levels has no edges to evaluate even in principle — nothing computes
per-course/chapter/exercise availability today (`fn_chapter_available`, `fn_course_available`,
`fn_roadmap_course_available`, `fn_exercise_available` were the functions that would have; they're
gone too). Only lesson-level `'graph'` mode does anything.

## 3. Lesson-level application — the one live level

`saveCurriculum` (learning-service) derives edges from curriculum order every time a course's
curriculum is saved (`deriveLessonSources`, `domain/model/curriculum.ts`), then switches the course
to `progression_mode = 'graph'` so `fn_lesson_available` actually evaluates them:

```
Lesson 1 "Biến & kiểu dữ liệu"
   ├──▶ Lesson 2 "if/else"
   ├──▶ Lesson 3 "Vòng lặp"
   ├──▶ Lesson 4 "Mảng"
   └──▶ Lesson 5 "Hàm"

After L1, all of L2–L5 unlock and may be completed in any order.
```

Combined with a join — lesson N needs lesson N-1 *in the same chapter*; the first lesson of a new
chapter needs **every** lesson of the chapter before it (not just the last one), because a mid-chapter
lesson may itself be marked `isPreview`/`skipOrder` and break the chain:

```
Lesson 3 ──┐
           ├─(group 0: AND)──▶ Lesson 6 "Bài tập tổng hợp"
Lesson 5 ──┘
```

A lesson flagged "cho học trước" (`skipOrder`) gets no incoming edges at all — open regardless of
what precedes it. This is scoped to one course (cross-chapter edges within a course are allowed;
cross-course is rejected by a composite FK).

## 4. Validation

Enforced in the database, not assumed from the frontend.

| Invalid case | Mechanism |
| --- | --- |
| Self-reference (`A → A`) | `CHECK (source_lesson_id <> target_lesson_id)` |
| Duplicate edge | `PRIMARY KEY (target_lesson_id, source_lesson_id, group_index)` |
| Missing entity | `FOREIGN KEY … ON DELETE CASCADE` |
| **Cycle** | `BEFORE INSERT OR UPDATE` trigger running a recursive reachability probe |
| Cross-course edge | **composite FK** `(course_id, lesson_id) → lessons(course_id, id)` |
| Negative / sparse `group_index` | `CHECK (group_index >= 0)` |

Scope is enforced declaratively by carrying `course_id` on the edge row and pointing a composite
foreign key at a `(course_id, id)` unique constraint on `lessons` — no procedural code, and
impossible to bypass.

### 4.1 Cycle detection

Before inserting `source → target`, the trigger asks: *is `source` already reachable from `target`?*
If yes, the new edge closes a loop.

```sql
WITH RECURSIVE reachable(id) AS (
    SELECT target_id_being_inserted
  UNION
    SELECT p.target_id
    FROM lesson_prerequisites p
    JOIN reachable r ON p.source_lesson_id = r.id
)
SELECT 1 FROM reachable WHERE id = source_id_being_inserted;
```

If that returns a row → `RAISE EXCEPTION 'circular dependency'`. The probe is `UNION` (not
`UNION ALL`), so an existing cycle cannot make it loop forever. Cost is bounded by the number of
edges in one course, which is small by construction. `fn_prevent_dependency_cycle` is generic
(parameterised by table/column names) and was originally reused by all five levels; it's kept for
`lesson_prerequisites` alone now — the trigger on the other four tables went with those tables in
0021.

This catches indirect cycles, not just `A→B→A`:

```
A → B → C → A     rejected when C → A is inserted
```

In practice `deriveLessonSources` only ever emits edges that point strictly forward through
curriculum order, so it can't produce a cycle itself — this guard exists for direct writes, not
because the derivation needs it.

## 5. Worked example — the seed data

`postgres/seed/0001_seed.sql` still builds the lesson-level shapes:

| Shape | Where in seed |
| --- | --- |
| Branching | Course *Java Core*, Chapter 1: L1 → {L2, L3, L4} |
| AND join, cross-chapter | L2 **and** L3 → L5 "Class và Object" (start of chapter 2) |
| Linear (no edges) | Roadmap *Nhập môn Lập trình*: `progression_mode='linear'`, position gates instead |

The roadmap/course/chapter/exercise AND-OR examples that used to live here (Spring Boot needing
Java Core *and* SQL, the rate-limiter exercise needing the JWT guard *or* API pagination, the
branching roadmap-course graph) were removed along with their tables in `0021` — they were seed-only
demonstrations of a mechanism the application never authored through.
