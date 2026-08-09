# Dependency Model

One mechanism, applied at five levels. This document defines it once and then shows each level.

## 1. Ordering is not dependency

Two independent columns/concepts, never conflated:

| | Stored as | Means | Affects availability? |
| --- | --- | --- | --- |
| **Order** | `position int` on the child row | where it renders in the list | **No** |
| **Dependency** | a row in `*_prerequisites` | what must be finished first | **Yes** |

So this is legal and meaningful:

```
position 1  Lesson "Giới thiệu"          no prerequisites   → available immediately
position 2  Lesson "Bài tập tổng hợp"    requires 3 and 4   → locked
position 3  Lesson "Cú pháp"             no prerequisites   → available immediately
position 4  Lesson "Vòng lặp"            requires 3         → locked until 3 done
```

A learner sees them in authored order but may legitimately start with #1 or #3.

## 2. The edge

Every prerequisite table has the same three meaningful columns:

```sql
target_id     -- the thing being gated
source_id     -- the thing that must be completed first
group_index   -- smallint, default 0
```

Read as: *"`target` requires `source`"*. The edge points **from prerequisite to dependent**.

### 2.1 AND / OR via `group_index` (disjunctive normal form)

```
Edges in the SAME group are ANDed.
Different groups are ORed.
```

`target` is unlocked when **at least one group is fully satisfied**. This covers every case the
product needs, and every case it might need, with one `smallint`:

| Requirement | Rows `(source, group_index)` |
| --- | --- |
| No prerequisite | *(no rows)* |
| Only A | `(A,0)` |
| A **and** B | `(A,0), (B,0)` |
| A **or** B | `(A,0), (B,1)` |
| (A **and** B) **or** C | `(A,0), (B,0), (C,1)` |
| (A **or** B) **and** C | `(A,0),(C,0), (B,1),(C,1)` |

The last row shows the cost of DNF: a conjunction of disjunctions has to be expanded. That is an
acceptable trade — the alternative is an expression tree (`AND`/`OR`/`NOT` nodes with parent
pointers), which triples the query complexity to buy an expressiveness the product has never asked
for. DNF is stored flat, evaluated with one aggregate query, and can be migrated to a tree later
without discarding data. See `04-design-decisions.md §3`.

### 2.2 Availability query

The same shape at every level (lessons shown):

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
`fn_lesson_available(user_id, lesson_id)` plus the equivalents for chapters, courses, roadmap
courses and exercises, so the API layer never re-implements the rule.

### 2.3 Progression mode gates whether edges are enforced

Edges describe *structure*; mode decides whether that structure is **enforced** for a given learner.

| Mode | Behaviour |
| --- | --- |
| `free` | all content available; prerequisites are advisory (shown as "recommended first") |
| `graph` | the DNF prerequisite edges are evaluated — supports branching, AND, OR |
| `linear` | **`position` itself is the gate**: every earlier non-optional sibling must be completed. Edges are ignored, and none need to be authored |

`linear` is not "graph with a tidy shape" — it is a different rule, which is why a purely
sequential curriculum needs zero edge rows (see the *Nhập môn Lập trình* roadmap in the seed).

Resolution order for a learner: `enrollment.mode_override` → falls back to the container's
`progression_mode`. This is how one dataset serves both constrained and unconstrained learning
**without duplicating any content** — the requirement in §7 of the brief.

## 3. Per-level application

### 3.1 Roadmap → Course

Edges reference `roadmap_courses.id` (the membership row), **not** `courses.id`, so gating is
per-roadmap.

```
Roadmap "Backend Java"  progression_mode = 'graph'
  rc1 Java Core ──┬──▶ rc2 SQL cơ bản ──┐
                  └─────────────────────┴─(group 0: AND)──▶ rc3 Spring Boot ──▶ rc4 Dự án

Roadmap "Nhập môn"      progression_mode = 'linear'
  rc8 Tư duy    rc9 Lập trình C    rc10 Cấu trúc dữ liệu     (no edges — position gates)

Roadmap "Frontend"      progression_mode = 'free'
  rc5 HTML      rc6 CSS            rc7 JavaScript            (no edges — nothing gates)
```

Constraint: both endpoints must belong to the **same roadmap**, enforced by the composite
foreign key on `(roadmap_id, roadmap_course_id)`.

### 3.2 Course → Course (intrinsic)

Independent of any roadmap. Supports multiple prerequisites:

```
Java Core ──┐
            ├─(group 0: AND)──▶ Spring Boot REST API
SQL Basics ─┘
```

### 3.3 Chapter

Scoped to one course. Typically linear, but branching is representable:

```
Ch1 Cú pháp ──┬──▶ Ch2 OOP
              ├──▶ Ch3 Collections
              └──▶ Ch4 File I/O          (Ch2/3/4 independent after Ch1)
```

### 3.4 Lesson — branching required

Scoped to one course (cross-chapter edges within a course are allowed; cross-course is rejected).
This is the case the brief calls out explicitly: `order` alone cannot express it.

```
Lesson 1 "Biến & kiểu dữ liệu"
   ├──▶ Lesson 2 "if/else"
   ├──▶ Lesson 3 "Vòng lặp"
   ├──▶ Lesson 4 "Mảng"
   └──▶ Lesson 5 "Hàm"

After L1, all of L2–L5 unlock and may be completed in any order.
```

Combined with a join:

```
Lesson 3 ──┐
           ├─(group 0: AND)──▶ Lesson 6 "Bài tập tổng hợp"
Lesson 5 ──┘
```

### 3.5 Exercise — set-scoped

Exercise edges carry a `set_id`. The **same exercise** is therefore free-choice in the global
catalogue and gated inside a curated track, with no duplication:

```
Set "Nhập môn thuật toán"  progression_mode='graph'

  E1 Tìm kiếm tuyến tính
   ├──▶ E2 Tìm kiếm nhị phân ──▶ E5 Tìm nghiệm bằng chia đôi
   └──▶ E3 Sắp xếp nổi bọt   ──▶ E4 Sắp xếp trộn

Set "Top 100 phỏng vấn"    progression_mode='free'
  E1 E2 E3 E4 E5   (same exercises, no edges → all available)
```

A learner may additionally set `exercise_set_enrollments.progression_mode_override = 'free'` on the
first set to opt out of gating — the user-selectable toggle the brief asks for.

## 4. Validation

Enforced in the database, not assumed from the frontend.

| Invalid case | Mechanism |
| --- | --- |
| Self-reference (`A → A`) | `CHECK (source_id <> target_id)` |
| Duplicate edge | `PRIMARY KEY (target_id, source_id, group_index)` |
| Missing entity | `FOREIGN KEY … ON DELETE CASCADE` |
| **Cycle** | `BEFORE INSERT OR UPDATE` trigger running a recursive reachability probe |
| Cross-scope (lesson in another course) | **composite FK** `(course_id, lesson_id) → lessons(course_id, id)` |
| Cross-roadmap (roadmap_course edge) | **composite FK** `(roadmap_id, rc_id) → roadmap_courses(roadmap_id, id)` |
| Exercise edge outside its set | **composite FK** into `exercise_set_items(set_id, exercise_id)` |
| Prerequisite on archived content | trigger checking `status <> 'archived'` |
| Negative / sparse `group_index` | `CHECK (group_index >= 0)` |

Only the last two need triggers. Scope is enforced declaratively by carrying the scope column
on the edge row and pointing a composite foreign key at a `(scope, id)` unique constraint — no
procedural code, and impossible to bypass. `lessons.course_id` is denormalised for this purpose
and is itself held true by a composite FK to `chapters(course_id, id)`.

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
edges in one course/set, which is small by construction.

This catches indirect cycles, not just `A→B→A`:

```
A → B → C → A     rejected when C → A is inserted
```

## 5. Worked example — the seed data

`postgres/seed/0001_seed.sql` builds all four shapes so the model can be inspected without
authoring content:

| Shape | Where in seed |
| --- | --- |
| Linear | Roadmap *Backend Java*: 4 courses chained |
| Branching | Course *Java Core*, Chapter 1: L1 → {L2, L3, L4} |
| Unconstrained | Roadmap *Frontend Developer* (`progression_mode='free'`, zero edges) |
| Multiple prereqs (AND) | Course *Spring Boot REST API* requires *Java Core* **and** *SQL cơ bản* |
| Alternative prereqs (OR) | Exercise *Rate limiter* requires *JWT guard* **or** *API pagination* |
| Mode override | user `an@` sets *Nhập môn thuật toán* to `free` |
