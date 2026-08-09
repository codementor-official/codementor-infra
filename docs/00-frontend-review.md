# Frontend Review — Evidence Base for the Data Model

Source: `codementor-frontend` (Next.js 16, mock-data driven). Every field below was read out of
`src/types/*`, `src/data/*`, `src/lib/*` and the route components that consume them. This document
records **what the frontend actually models today** and **what should change** before it becomes a
database. It is the justification trail for `01-domain-model.md`; the schema does not invent
entities that cannot be traced back to something here.

## 1. Where the domain lives in the frontend

| Concern | Files |
| --- | --- |
| Learning hierarchy | `types/roadmap.ts`, `data/roadmaps.ts`, `lib/roadmap/*` |
| Lesson bodies | `data/lesson-content.ts` |
| Practice catalogue | `data/practice-items.ts`, `lib/practice/practice-recommendation.ts` |
| Solve workspace | `data/sample-problem.ts`, `app/solve/[exerciseId]` |
| Authoring | `types/authored-problem.ts`, `types/problem-draft.ts`, `data/authored-problems.ts` |
| Study groups | `types/study-group.ts`, `types/study-group-detail.ts`, `lib/study-group/*` |
| Submissions | `types/submission.ts`, `data/submission-history.ts` |
| Personalisation | `types/learning-preference.ts`, `lib/roadmap/recommendation.ts` |
| Articles | `data/articles.ts` |
| Identity | `components/profile/profile-management-page.tsx`, `app/login`, `app/signup` |

## 2. Entity inventory and field disposition

Legend — **KEEP**: persist as-is (possibly renamed/retyped). **DROP**: presentational or derivable,
not persisted. **DERIVE**: computed at read time. **CACHE**: derived but materialised for read
performance. **MOVE**: belongs on a different entity. **ADD**: missing, required by the domain.

### 2.1 `LearningRoadmap`

| Frontend field | Type | Disposition | Note |
| --- | --- | --- | --- |
| `id`, `slug`, `title` | string | KEEP | `slug` unique |
| `shortDescription`, `description` | string | KEEP | |
| `thumbnail` | `"{ }"`, `"Jv"` | DROP → ADD `cover_image_url` | Mono glyph is a UI placeholder, not content |
| `field` | enum(6) | KEEP | becomes `roadmap_field` enum |
| `level` | `CurrentLevel` | KEEP | shared enum with courses |
| `technologies[]` | string[] | KEEP → normalise | free strings collide (`"C/C++"` vs `"C++"`); becomes `technologies` + join table |
| `estimatedHours` | number | CACHE | should equal Σ course hours; kept as an authored override |
| `prerequisites[]` | **string[] of prose** | DROP → ADD real edges | `"Đã hoàn thành Lập trình C cơ bản"` is not a relationship |
| `learningOutcomes[]`, `targetAudience[]` | string[] | KEEP | ordered child tables |
| `courses[]` | `Course[]` | KEEP → junction | ordering + gating are roadmap-scoped, not course properties |
| `popularity` | 0-100 | CACHE | arbitrary today; derive from enrolments |
| `updatedAt` | string | KEEP | retype to `timestamptz` |
| `userProgress` | object\|null | **MOVE** | per-user state on a content record — see §3.1 |

### 2.2 `Course`

| Frontend field | Disposition | Note |
| --- | --- | --- |
| `id`, `slug`, `title`, `description` | KEEP | |
| `thumbnail` | DROP → `cover_image_url` | as above |
| `level`, `durationHours` | KEEP | |
| `technologies[]` | KEEP → normalise | |
| `prerequisites[]` (prose) | DROP → ADD edges | see §3.2 |
| `outcomes[]` | KEEP | ordered child table |
| `totalChapters`, `totalLessons` | CACHE | authored as "realistic totals before curriculum exists" — legitimate, but must be reconcilable |
| `chapters[]` | KEEP | |
| `status` | **MOVE** | `not-started/in-progress/completed/locked` is per-user |
| `progressPercent` | **MOVE** | per-user |
| `instructor` | KEEP → **FK** | free string `"Nguyễn Minh Anh · Frontend Mentor"` conflates name + title |
| `rating`, `ratingCount` | CACHE → ADD `course_reviews` | aggregates with no source of truth are unauditable |
| `studentCount` | CACHE | derive from enrolments |

### 2.3 `Chapter` / `Lesson`

| Frontend field | Disposition | Note |
| --- | --- | --- |
| `Chapter.order` | KEEP as `position` | **display order only** — see §3.3 |
| `Chapter.description` | KEEP | |
| `Lesson.type` | KEEP | video/article/exercise/quiz/challenge/project (all six used in seed) |
| `Lesson.durationMinutes` | KEEP | |
| `Lesson.isPreview` | KEEP | genuine content attribute (free preview) |
| `Lesson.isLocked` | **DROP → derive** | hardcoded on 4 seed rows; must be computed from prerequisites + user progress |
| `Lesson.isCompleted` | **MOVE** | per-user |
| — | ADD `exercise_id` | `type: "exercise"` lessons have no link to the exercise they run |
| — | ADD `position` | lessons have implicit array order with no stored field |

`LessonContent` (`data/lesson-content.ts`): `summary`, `objectives[]`, `sections[{heading,
paragraphs[]}]`, `code{label,language,value}`, `exerciseBrief[]` — variable-shape rich body,
**document-oriented**, keyed by lesson title (fragile; needs a real lesson id).

### 2.4 Exercises — four incompatible shapes for one concept

This is the single largest inconsistency in the frontend.

| Shape | Where | Fields unique to it |
| --- | --- | --- |
| `PracticeItem` | practice catalogue | `fields[]`, `goals[]`, `xp`, `popularity`, `topic`, `acceptanceRate`, `companies[]`, `isDaily`, `isFavorite`, `status` |
| `Problem` | solve workspace | `constraints[]`, `testCases[{input,expected}]`, `starter{lang:code}` |
| `AuthoredCodeProblem` | authoring bank | `statement`, `examples[]`, `solveSlug`, `languageCount`, `testCaseCount`, `solverCount`, `assignedGroups[]` |
| `GroupExercise` | study group | `source(ai/manual)`, 8-state `status`, `dueAt`, `xp`, `objective`, `criteria`, `phase`, `refDoc`, `hints[]`, `supportLanguages[]`, `timeLimit`, `memoryLimit`, review-workflow fields |

They describe the same object at different lifecycle stages. Consolidated into **one** exercise
(relational spine + document body) with a lifecycle `status`, plus a separate *assignment* concept
for the group case. Notable per-shape decisions:

- `difficulty` uses three vocabularies — `"Cơ bản"/"Trung bình"/"Nâng cao"` (display), `easy/medium/hard`
  (authoring), and `PracticeItem.level`. Collapse to one enum; Vietnamese labels are a presentation concern.
- `acceptanceRate`, `solverCount`, `participants: "5.842"` (a *formatted string*) → integer counters, CACHE.
- `isFavorite`, `status(solved/attempted/todo)` → per-user, MOVE.
- `estTime: "30 phút"`, `timeLimit`, `memoryLimit`, `sizeLabel: "2.4 MB"` → typed numerics, not display strings.
- `companies[]`, `isDaily` → keep (`companies` normalised; `isDaily` becomes a scheduled feature row).
- `phase`, `refDoc`, `criteria`, `objective` → group-authored teaching metadata; keep on the document body.

### 2.5 Users and identity

The frontend has no user type. Fields are scattered across components:

| Source | Fields |
| --- | --- |
| `profile-management-page.tsx` | `name`, `handle`, `bio`, `website`, `github` |
| `GroupMember` | `xp`, `solvedCount`, `streakDays`, `joinedAt`, `lastActiveMinutesAgo`, `achievements[]` |
| `submission-history` | authorship of submissions |
| memory/auth | email |

ADD: `email` (unique, required), `password_hash`, `email_verified_at`, `avatar_url`, `locale`,
`timezone`, `status`, `role` (platform-level: learner/mentor/admin — `/admin` route exists),
`created_at`. `initials` is DROP (derivable). `lastActiveMinutesAgo` → `last_active_at timestamptz`
(a relative number cannot be stored). `xp`/`solvedCount`/`streakDays` are CACHE.

### 2.6 `LearningPreference`

Persist whole (it drives recommendations): `learningGoal`, `interestedFields[]`, `currentLevel`,
`interestedTechnologies[]`, `weeklyStudyHours`, `careerGoal`, `preferredLearningStyle[]`,
`contentPriority`, `remindersEnabled`, `reminderTime`, `adaptiveRecommendations`.
`weeklyStudySchedule` is a fixed 7-key record of `{enabled, startTime, durationMinutes}` → its own
child table keyed by weekday (queryable for the reminder scheduler; a JSON blob would not be).

`RecommendationResult` (`score`, `matchedReasons[]`) is computed by `lib/roadmap/recommendation.ts`
at runtime from weights — **never persisted**.

### 2.7 Study groups

`StudyGroup`: `name`, `description`, `code` (invite, unique), `topic`, `role`, `ownerName` KEEP;
`tile` DROP; `memberCount`/`openTaskCount`/`progressPercent` CACHE; `lastActiveMinutesAgo` → timestamp;
`memberPreview[]` DROP (a query limit, not data).

`GroupMember` → `group_members` junction (user × group) carrying `role`, `joined_at`,
`permission_overrides`. `achievements[]`, `technologies[]`, `courses[]` on the member are *views of
platform-wide user data*, not group data — DROP from the junction.

`RolePermissions` + `permissionOverrides` + `effectiveMemberPermissions()` — a real two-layer
permission model (role defaults per group, per-member overrides). Persist both layers.

`GroupDocument`: `status`(5) + `verdict`(3) are **two independent axes** (human moderation state vs
AI pre-screen) — keep both. `sizeLabel` → `size_bytes`. `previewText`/`url` are format-dependent.

`Assignment` + `AssignmentSubmission`: assignment = (exercise × member) with `attemptLimit`,
`allowRetry`, `allowLateSubmission`, `dueAt`; submissions are versioned attempts. `result: "Đạt"/"Không đạt"`
→ verdict enum.

### 2.8 Submissions

`SubmissionHistoryItem` and `AssignmentSubmission` are the same event with different fields
(`origin: "Nhóm học tập" | "Bài luyện tập"` already hints at the unification). One `submissions`
table with a nullable assignment link. `runtime: "12ms"`, `memory: "3.2MB"` → integers.

### 2.9 Articles

`slug`, `title`, `excerpt`, `author`, `role`, `readMinutes`, `tag`, `publishedAt`, `takeaway` KEEP;
`sections[]` is a variable-shape body → document store. `author`+`role` → FK to users.

## 3. Cross-cutting findings

### 3.1 Content and per-user state are conflated (most important)

`Lesson.isCompleted`, `Lesson.isLocked`, `Course.status`, `Course.progressPercent`,
`Roadmap.userProgress`, `PracticeItem.status`, `PracticeItem.isFavorite` all sit on **shared content
records**. In a single-user mock this is invisible; with real users it is a correctness bug — two
learners would overwrite each other's progress. All of these move to `*_progress` / `*_enrollments`
tables keyed by `(user_id, entity_id)`.

### 3.2 Prerequisites are prose, not relationships

`Course.prerequisites = ["Đã hoàn thành Java Core"]` cannot be evaluated, validated, or used to
compute availability. Replaced by real edge tables; the human sentence is preserved separately as
`prerequisite_note` for display, because some prerequisites genuinely aren't links
(`"Biết sử dụng máy tính cơ bản"`).

### 3.3 Ordering is doing double duty

`Chapter.order` and lesson array position currently imply *both* display sequence and progression.
`isLocked` being hand-set on 4 lessons is the workaround. These are separated into `position`
(display) and prerequisite edges (gating) — a lesson can be second in the list with no prerequisite,
or last with none.

### 3.4 No progression mode exists

The product requires constrained and unconstrained learning, user-selectable. Nothing in the
frontend expresses this. ADD `progression_mode` at roadmap / course / exercise-set level, plus a
per-learner override.

### 3.5 Formatted strings used as data

`participants: "5.842"`, `updated: "Cập nhật hôm nay"`, `estTime: "30 phút"`, `sizeLabel: "2.4 MB"`,
`runtime: "12ms"`, `lastActiveMinutesAgo: 8`. All become typed columns; formatting is the frontend's job.

### 3.6 Free-text vocabularies that need normalising

`technologies[]`, `tags[]`, `topic`, `companies[]`, `Article.tag`, `GroupDocument.type` — the same
concept appears with inconsistent spellings across files. Normalised into lookup tables so filters
are reliable.

## 4. What the frontend does *not* need to change

The schema is designed so the existing screens keep working. Fields that moved to per-user tables
are still served to the UI in the same shape (`course.progressPercent` becomes a join result rather
than a column). No frontend change is required by this model beyond eventually replacing the mock
services in `lib/*/*-service.ts` with API calls — which was already their stated purpose
(*"shaped like a future REST/GraphQL client"*, `roadmap-service.ts`).

Two inconsistencies would benefit from a later frontend follow-up, but are **not** blocking and were
not changed as part of this task:

1. `difficulty` should settle on one vocabulary and render Vietnamese labels at the edge.
2. `lesson-content.ts` keys lesson bodies by **title** — this breaks the moment two lessons share a
   title (already true: `"Java Core"` appears as both a course title and a shallow-course title).
