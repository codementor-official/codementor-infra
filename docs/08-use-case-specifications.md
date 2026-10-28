# Detailed use case specifications

Full specifications for **8 key use cases**, chosen because they have real `«include»`/`«extend»`
relationships, carry business rules enforced by the database, or set this project apart.

The remaining use cases in [`07-use-case-model.md`](07-use-case-model.md) follow the same template
as §0.

---

## 0. Specification template

| Field | Meaning |
| --- | --- |
| **Code / Name** | Unique identifier |
| **Primary actor** | Who initiates it, with a goal |
| **Supporting actor** | External system that is called |
| **Precondition** | Must hold *before* it starts |
| **Postcondition** | Guaranteed *after* it ends successfully |
| **Trigger** | The opening event |
| **Main flow** | The success scenario |
| **Alternative flows** | Branches that still succeed (`3a`, `3b`…) |
| **Exception flows** | Failures (`E1`, `E2`…) |
| **Business rules** | Constraints, with where they are enforced |

---

## UC-01 — Sign up

| | |
| --- | --- |
| **Primary actor** | Guest |
| **Supporting actor** | Notification service |
| **Relationship** | `«include»` UC-04 Verify email |
| **Precondition** | Not signed in |
| **Postcondition** | A `users` record exists, with `email_verified_at IS NULL` until verified |

**Main flow**

1. The guest opens the sign-up page.
2. Enters email, password and full name.
3. The system checks the email is not already registered.
4. The system hashes the password and creates a `users` record with `role='learner'`,
   `status='active'`.
5. **«include» UC-04** — sends the verification email.
6. The system tells the guest to check their inbox.

**Alternative flows**

- *4a.* The guest signs up through OAuth → `password_hash` stays NULL, `email_verified_at` is set
  immediately.

**Exception flows**

- *E1.* The email already exists → show an error without revealing the account's state
  *(prevents account enumeration)*.
- *E2.* Sending the email fails → the account is still created and the email can be resent.
  **No** rollback.

**Business rules**

| Code | Rule | Enforced by |
| --- | --- | --- |
| BR-01 | Email is unique, case-insensitive | `users.email citext UNIQUE` |
| BR-02 | `handle` uses only `a-z 0-9 _ -`, 3–30 characters | CHECK `users_handle_format` |
| BR-03 | Accounts are never hard-deleted | convention: use `status='deleted'` |

---

## UC-20 — Study a lesson

| | |
| --- | --- |
| **Primary actor** | Learner |
| **Relationship** | `«include»` UC-21 · `«extend»`ed by UC-24 |
| **Precondition** | Signed in; enrolled in the course containing the lesson |
| **Postcondition** | `lesson_progress` exists with `status ∈ {in_progress, completed}` |

**Main flow**

1. The learner picks a lesson from the chapter list.
2. **«include» UC-21** — the system decides whether the lesson is unlocked for this learner.
3. The system loads the content from Mongo `lesson_contents` using `lessons.content_ref`.
4. If there is no progress record yet → create `lesson_progress(status='in_progress',
   started_at=now())`.
5. Show the content, the lesson objectives and previous/next navigation.

**Alternative flows**

- *3a.* A `video` lesson → restore the playback position from `last_position_seconds`.
- *3b.* An `exercise` lesson with `lessons.exercise_id IS NOT NULL` → open the workspace (go to
  UC-33).
- *3c.* `content_ref IS NULL` → show an "in preparation" state.

**Exception flows**

- *E1.* UC-21 returns `false` → show why it is locked, with **the list of missing
  prerequisites**, and do not open the content.
- *E2.* The Mongo document is missing although `content_ref` is set → report a content error and
  log it. *(Cannot happen for published lessons — see BR-11.)*

**Business rules**

| Code | Rule | Enforced by |
| --- | --- | --- |
| BR-10 | A lesson with `is_preview = true` can be viewed without enrolling | application logic |
| BR-11 | Published content always has a body | CHECK `..._published_needs_content` |

---

## UC-21 — Check unlock conditions  *(included)*

The **most important** use case of the project: it fully replaces the old `isLocked` flag, which
was hard-coded on the data and could not differ between learners.

| | |
| --- | --- |
| **Primary actor** | *(none — always included)* |
| **Precondition** | The lesson exists |
| **Postcondition** | Returns `true`/`false` + the list of unmet conditions |

**Main flow**

1. Find the course containing the lesson (`lessons.course_id`).
2. Determine the **effective learning mode**:
   `COALESCE(course_enrollments.mode_override, courses.progression_mode)`.
3. Branch on the mode:

| Mode | Rule |
| --- | --- |
| `free` | Return `true` immediately — every lesson is open |
| `linear` | Return `true` when **every non-optional lesson before it** (by `chapter.position`, `lesson.position`) is complete. **The edge table is not read** |
| `graph` | Return `true` when there is no prerequisite edge, **or** at least one `group_index` has **all** of its edges complete |

**`graph` evaluation example (DNF)**

```
Edges of "Classes and objects":  (Data types, group 0)
                                 (Operators,  group 0)
→ group 0 is an AND  →  BOTH must be complete
```

OR (two different `group_index` values on the same target) is part of the mechanism, but no real
edge uses it: `deriveLessonSources` (learning-service) always produces exactly one group per
lesson, derived from the chapter/lesson order — see `02-dependency-model.md §2.1`. The example
"Rate limiter needs JWT guard OR API pagination" once illustrated OR at the exercise level, but the
`exercise_prerequisites` table and `fn_exercise_available` were removed in `0021` (they never had
an application caller).

**Business rules**

| Code | Rule | Enforced by |
| --- | --- | --- |
| BR-20 | `position` carries **no** prerequisite meaning in `graph` mode | design: the two concepts live in separate tables |
| BR-21 | A lesson is "complete" when `lesson_progress.status='completed'` | `fn_lesson_available` |
| BR-22 | An `is_optional` lesson does not block progress | the `NOT l.is_optional` clause |

**Implementation:** `fn_lesson_available(user_id, lesson_id)` — migration `0011`.
Verified by: `postgres/verify.sql` section B.

---

## UC-26 / UC-31 — Choose constrained or free learning

Directly implements the requirement *"support both sequential and free learning without
duplicating content"*.

| | |
| --- | --- |
| **Primary actor** | Learner |
| **Relationship** | `«extend»` UC-21 (lessons) / UC-32 (exercises) |
| **Precondition** | Enrolled in the course or the exercise set |
| **Postcondition** | `mode_override` is written; **no** content record changes |

**Main flow**

1. The learner opens the learning-mode option.
2. The system shows the default mode set by the content author.
3. The learner picks *Sequential* / *Graph* / *Free*.
4. Write to `course_enrollments.mode_override` or
   `exercise_set_enrollments.progression_mode_override`.
5. Every later unlock check uses the new value.

**Alternative flows**

- *3a.* "Use default" is chosen → write `NULL`, inheriting the content's mode again.

**Business rules**

| Code | Rule | Notes |
| --- | --- | --- |
| BR-30 | Changing mode does **not** affect other learners | `mode_override` lives on the enrollment record |
| BR-31 | Changing mode does **not** delete prerequisite edges | in `free`, edges are only suggestions |
| BR-32 | Content is never duplicated to serve two modes | the same `exercises` row appears in a `graph` set and a `free` set |

---

## UC-35 — Submit a solution

| | |
| --- | --- |
| **Primary actor** | Learner |
| **Supporting actor** | Grading system |
| **Relationship** | `«include»` UC-36 · `«extend»`ed by UC-37, UC-72 |
| **Precondition** | The exercise is unlocked (UC-32); there is source code |
| **Postcondition** | A `submissions` record exists; `exercise_progress` is updated |

**Main flow**

1. The learner clicks *Submit*.
2. The system works out the next `attempt_number` for the (learner, exercise) pair.
3. Create `submissions` with `verdict='pending'`.
4. **«include» UC-36** — send the source code + every test case to the grading system.
5. Receive the result: verdict, tests passed, time, memory.
6. Write per-test details to Mongo `submission_run_details` and store `run_detail_ref`.
7. Update `exercise_progress`: `attempt_count += 1`; if `verdict='accepted'`, set
   `status='solved'`, `first_solved_at` (if not set yet) and `best_score`.
8. Show the result — hidden tests show only *pass/fail*, never their inputs or outputs.

**Alternative flows**

- *2a.* **«extend» UC-37** — past `due_at` with `allow_late_submission = true`
  → set `submissions.is_late = true` and grade as usual.
- *8a.* **«extend» UC-72** — verdict ≠ `accepted` and the learner asks the AI to analyse the error.

**Exception flows**

- *E1.* Past `due_at` with `allow_late_submission = false` → reject the submission.
- *E2.* The assignment's `attempt_limit` is exceeded → reject.
- *E3.* Compile error → `verdict='compile_error'`, `score=0`; the submission **is still stored**.
- *E4.* The grading system does not respond → keep `verdict='pending'` and allow regrading. The
  submission is **not** lost.

**Business rules**

| Code | Rule | Enforced by |
| --- | --- | --- |
| BR-40 | `attempt_number` is unique per (learner, exercise) | UNIQUE `(user_id, exercise_id, attempt_number)` |
| BR-41 | `passed_tests ≤ total_tests` | CHECK `submissions_passed_le_total` |
| BR-42 | An exercise with submissions cannot be deleted | FK `ON DELETE RESTRICT` |
| BR-43 | Group submissions have an `assignment_id`; free practice has NULL | nullable column — no type column needed |
| BR-44 | Grading details expire after 180 days; the verdict does not | Mongo TTL index |

---

## UC-47 / UC-48 — Set prerequisites & check for cycles

| | |
| --- | --- |
| **Primary actor** | Administrator |
| **Relationship** | UC-47 `«include»` UC-48 |
| **Precondition** | Both items share a scope (same course / same path / same set) |
| **Postcondition** | The edge is written, or rejected with a reason; the graph is always a DAG |

**Current state:** the specification below describes the original design (5 levels).
`0021_drop_unused_prerequisite_graph.sql` removed 4 of the 5 `*_prerequisites` tables
(chapter/course/roadmap_course/exercise) and the matching `fn_*_available` functions because no
use case or DTO ever wrote to them — no lecturer studio has a UI for graph-style prerequisites. The
only surviving level is **lessons**, where edges are **derived automatically** from the
chapter/lesson order (`deriveLessonSources`) when the curriculum is saved — no "administrator
picks the logical relationship" flow runs in the application. See `02-dependency-model.md`.

**Main flow (original design, no longer implemented outside lessons)**

1. The administrator picks the item that needs a condition (lesson / chapter / course / exercise).
2. Picks one or more prerequisite items.
3. Picks the logical relationship:
   - *All of* → the same `group_index`
   - *One of* → a different `group_index` for each
4. **«include» UC-48** — the database checks for cycles before writing.
5. Write the edge to the matching `*_prerequisites` table.

**Exception flows**

| Code | Case | Blocked by | SQLSTATE |
| --- | --- | --- | --- |
| E1 | Self-reference (A→A) | CHECK `*_no_self_reference` | `23514` |
| E2 | Duplicate edge | PRIMARY KEY | `23505` |
| E3 | **Direct cycle** (A→B, then B→A) | trigger `fn_prevent_dependency_cycle` | `23514` |
| E4 | **Indirect cycle** (A→B→C→A) | the same trigger, walking recursively | `23514` |
| E5 | Different scope (a lesson from another course) | composite FOREIGN KEY | `23503` |
| E6 | The item does not exist | FOREIGN KEY | `23503` |
| E7 | Points at archived content | trigger `fn_reject_archived_*` | `23514` |

**How cycles are detected:** before adding *"S must come before T"*, follow the edges forward from
**T** and see whether **S** is reachable. If it is, the new edge closes a loop. `UNION` (not
`UNION ALL`) is used, so pre-existing bad data cannot make it hang.

**Business rules**

| Code | Rule | Notes |
| --- | --- | --- |
| BR-50 | The prerequisite graph is always a DAG | no exceptions |
| BR-51 | A path's conditions point at `roadmap_courses.id`, not `courses.id` | so one course can be locked in one path and free in another |
| BR-52 | An exercise edge belongs to **one set** | the same exercise can be locked in set A and free in set B |

Verified by: `postgres/verify.sql` section C — all 7 cases are asserted to be rejected.

---

## UC-53 — Upload a document to the group

| | |
| --- | --- |
| **Primary actor** | Group member |
| **Supporting actor** | AI service |
| **Relationship** | `«include»` UC-54 AI pre-check, UC-5B Record activity |
| **Precondition** | An `active` member; **`uploadDoc` permission = true** |
| **Postcondition** | `group_documents` is created with two independent status axes |

**Main flow**

1. The member picks a file or pastes a link, and enters a title and a topic.
2. The system checks the effective `uploadDoc` permission *(role permission overlaid with the
   personal override)*.
3. Store the file in object storage and record `storage_key`; or record `url` for a link.
4. **«include» UC-54** — send the content to the AI service for a pre-check → receive `ai_verdict`.
5. Create `group_documents` with `status='pending'` and the `ai_verdict` just received.
6. **«include» UC-5B** — record the activity in `group_activities`.
7. The document enters the review queue (UC-55).

**Alternative flows**

- *4a.* `ai_verdict='valid'` and the group has auto-approval on → `status='published'` at once.
- *4b.* The AI service does not respond → default to `ai_verdict='valid'`, flagged for a closer
  human look. The upload is **not** blocked.

**Exception flows**

- *E1.* No `uploadDoc` permission → reject.
- *E2.* Unsupported file type or too large → reject before storing.

**Business rules**

| Code | Rule | Enforced by |
| --- | --- | --- |
| BR-60 | A `Link` document must have a `url`; a file document must have a `storage_key` | CHECK `group_documents_body_present` |
| BR-61 | `status` (reviewer) and `ai_verdict` (machine) are **two independent axes** | two separate columns |
| BR-62 | Only `published` documents are visible to regular members | application logic |

---

## UC-58 — Grade & give feedback on group submissions

| | |
| --- | --- |
| **Primary actor** | Group manager |
| **Precondition** | **`reviewSubmission` permission = true**; a submission exists |
| **Postcondition** | `assignments.review_status` is no longer `pending`; `reviewed_by`, `reviewed_at` are set |

**Main flow**

1. The reviewer opens the group's grading queue.
2. Picks a submission and views its source code and automatic grading result.
3. Writes feedback and chooses *Pass* or *Needs fixes*.
4. Update `assignments`: `review_status`, `feedback`, `reviewed_by`, `reviewed_at`.
5. **«include» UC-5B** — record the activity.

**Alternative flows**

- *3a.* *Needs fixes* is chosen → `review_status='needsfix'`; the member resubmits if
  `allow_retry=true`.

**Exception flows**

- *E1.* No `reviewSubmission` permission → reject. *Note: a specific deputy can lose this
  permission through `group_member_permissions`.*
- *E2.* Grading one's own submission → reject *(application rule)*.

**Business rules**

| Code | Rule | Enforced by |
| --- | --- | --- |
| BR-70 | `review_status='pending'` ⟺ `reviewed_at IS NULL` | CHECK `assignments_reviewed_consistency` |
| BR-71 | The submission and the reviewer belong to the same group | composite FK `assignments_member_in_group` |
| BR-72 | A member with `role='owner'` always has every permission | not stored in `group_role_permissions`; the resolver defaults to `true` |

---

## UC-51 — Join a group with an invite code

| | |
| --- | --- |
| **Primary actor** | Learner |
| **Precondition** | Signed in; not yet a member of that group |
| **Postcondition** | `group_members(role='member', status='active')`; `member_count` is updated |

**Main flow**

1. The learner enters an invite code.
2. The system looks up `study_groups.invite_code` *(case-insensitive)*.
3. Checks the group has `status='active'`.
4. Creates `group_members` with `role='member'`.
5. A trigger updates `study_groups.member_count`.

**Exception flows**

- *E1.* The code does not exist → a generic error that does **not** reveal whether the group exists.
- *E2.* Already a member → go straight into the group.
- *E3.* The group is archived → reject.

**Business rules**

| Code | Rule | Enforced by |
| --- | --- | --- |
| BR-80 | Invite codes are unique, 5–12 alphanumeric characters | UNIQUE + CHECK `study_groups_invite_code_format` |
| BR-81 | One record per person per group | UNIQUE `(group_id, user_id)` |
| BR-82 | Exactly one owner per group | UNIQUE INDEX `uq_group_members_single_owner` |

---

## Appendix — Business rules

| Codes | Summary | Enforced by |
| --- | --- | --- |
| BR-01…03 | Account identity | UNIQUE, CHECK |
| BR-10…11 | Content access | CHECK + application |
| BR-20…22 | Unlock conditions | `fn_lesson_available` |
| BR-30…32 | Learning modes | `mode_override` |
| BR-40…44 | Submission & grading | UNIQUE, CHECK, FK RESTRICT, TTL |
| BR-50…52 | Dependency graph integrity | trigger + composite FK |
| BR-60…62 | Group documents | CHECK |
| BR-70…72 | Reviews & permissions | CHECK + composite FK |
| BR-80…82 | Group membership | UNIQUE + partial index |

**36 of the 40 rules are enforced in the database**, independent of the application remembering
to check — exactly the principle set in [`04-design-decisions.md`](04-design-decisions.md).
