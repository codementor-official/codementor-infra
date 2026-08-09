# Domain Model & PostgreSQL ERD

Derived from `00-frontend-review.md`. Every entity here traces to something the frontend actually
does; nothing was added speculatively. Grouped into five bounded contexts.

## 0. Contexts at a glance

| Context | Owns | Store |
| --- | --- | --- |
| Identity & personalisation | users, preferences, cached stats | PostgreSQL |
| Taxonomy | technologies, tags, companies | PostgreSQL |
| Learning content | roadmaps → courses → chapters → lessons, exercises, exercise sets | PostgreSQL (spine) + MongoDB (bodies) |
| Progression | enrolments, per-user progress, dependency evaluation | PostgreSQL |
| Collaboration | study groups, documents, assignments, submissions | PostgreSQL (+ MongoDB run details) |

## 1. Identity & personalisation

```mermaid
erDiagram
    users ||--o| user_stats : "cached totals"
    users ||--o| learning_preferences : "survey"
    learning_preferences ||--o{ learning_preference_technologies : "interested in"
    learning_preferences ||--o{ study_schedule_slots : "weekly plan"
    technologies ||--o{ learning_preference_technologies : ""

    users {
        uuid id PK
        citext email UK "required, unique"
        text password_hash
        citext handle UK "nullable, unique"
        text display_name
        text bio
        text avatar_url
        text website_url
        text github_handle
        platform_role role "learner|mentor|admin"
        account_status status "active|suspended|deleted"
        timestamptz email_verified_at
        timestamptz last_active_at
        timestamptz created_at
    }
    user_stats {
        uuid user_id PK_FK
        int xp "CACHE"
        int solved_count "CACHE"
        int current_streak_days "CACHE"
        int longest_streak_days "CACHE"
        date last_solved_on
    }
    learning_preferences {
        uuid user_id PK_FK
        text learning_goal
        current_level current_level
        roadmap_field[] interested_fields
        learning_style[] preferred_learning_styles
        int weekly_study_hours
        text career_goal
        content_priority content_priority
        bool reminders_enabled
        time reminder_time
        bool adaptive_recommendations
    }
    study_schedule_slots {
        uuid user_id PK_FK
        weekday weekday PK
        bool enabled
        time start_time
        int duration_minutes
    }
```

`user_stats` is split from `users` deliberately: it is a **write-hot cache** (updated on every
accepted submission) while `users` is read-hot and rarely written. Keeping them apart avoids row
contention on the identity record.

`interested_fields` and `preferred_learning_styles` are **native enum arrays**, not JSON — they are
typed, constrained, and GIN-indexable. `study_schedule_slots` is a real table because the reminder
scheduler must query *"which users have a session starting at 19:00 on Monday"* across all users.

## 2. Learning content

```mermaid
erDiagram
    roadmaps ||--o{ roadmap_courses : "contains"
    courses  ||--o{ roadmap_courses : "appears in"
    roadmap_courses ||--o{ roadmap_course_prerequisites : "gated by"
    courses ||--o{ course_prerequisites : "gated by"
    courses ||--o{ chapters : "owns"
    chapters ||--o{ chapter_prerequisites : "gated by"
    chapters ||--o{ lessons : "owns"
    lessons ||--o{ lesson_prerequisites : "gated by"
    lessons }o--o| exercises : "type=exercise runs"
    users ||--o{ courses : "instructs"
    courses ||--o{ course_reviews : "rated by"
    exercise_sets ||--o{ exercise_set_items : "curates"
    exercises ||--o{ exercise_set_items : "member of"
    exercise_sets ||--o{ exercise_prerequisites : "scopes"

    roadmaps {
        uuid id PK
        citext slug UK
        text title
        text short_description
        text description
        roadmap_field field
        current_level level
        text cover_image_url
        int estimated_hours "authored override"
        progression_mode progression_mode "linear|graph|free"
        text prerequisite_note "prose, display only"
        content_status status
        int popularity_score "CACHE"
        timestamptz published_at
    }
    courses {
        uuid id PK
        citext slug UK
        text title
        text description
        text cover_image_url
        current_level level
        int duration_hours
        uuid instructor_id FK
        text prerequisite_note "prose, display only"
        progression_mode progression_mode
        content_status status
        int total_chapters "CACHE"
        int total_lessons "CACHE"
        numeric rating_avg "CACHE"
        int rating_count "CACHE"
        int enrollment_count "CACHE"
    }
    roadmap_courses {
        uuid id PK
        uuid roadmap_id FK
        uuid course_id FK
        int position "DISPLAY ORDER"
        bool is_optional
    }
    chapters {
        uuid id PK
        uuid course_id FK
        text title
        text description
        int position "DISPLAY ORDER"
    }
    lessons {
        uuid id PK
        uuid chapter_id FK
        text title
        lesson_type type
        int duration_minutes
        bool is_preview
        int position "DISPLAY ORDER"
        uuid exercise_id FK "nullable"
        text content_ref "-> mongo lesson_contents"
    }
    exercises {
        uuid id PK
        citext slug UK
        text title
        text summary
        exercise_difficulty difficulty
        exercise_kind kind "code|theory|quiz"
        exercise_status status
        exercise_source source "ai|manual"
        int xp_reward
        int estimated_minutes
        int time_limit_ms
        int memory_limit_kb
        uuid author_id FK
        uuid owner_group_id FK "nullable, group-private"
        text content_ref "-> mongo exercise_contents"
        numeric acceptance_rate "CACHE"
        int solver_count "CACHE"
    }
    exercise_sets {
        uuid id PK
        citext slug UK
        text title
        exercise_set_kind kind "collection|track|daily"
        progression_mode progression_mode "default for learners"
    }
```

Key structural decisions:

- **`roadmap_courses` is a first-class entity, not a plain join.** Position and gating are properties
  of *"this course inside this roadmap"*, not of the course. The same course can sit at position 2
  in one roadmap with prerequisites and at position 5 in another with none. Prerequisite edges
  therefore reference `roadmap_courses.id`, not `courses.id`.
- **Two levels of course prerequisite.** `course_prerequisites` is *intrinsic* ("Spring Boot REST API
  needs Java Core, wherever you meet it"); `roadmap_course_prerequisites` is *curricular* (this
  roadmap's chosen sequence). The frontend conflates them into one prose array; the domain does not.
- **`exercises` keeps a relational spine** even though its body lives in MongoDB — because
  dependencies, progress, assignments and set membership all need enforceable foreign keys. See
  `04-design-decisions.md §1`.
- **`content_ref`** is the MongoDB `_id` as text. It is nullable while content is being authored.

## 3. Progression

```mermaid
erDiagram
    users ||--o{ roadmap_enrollments : ""
    users ||--o{ course_enrollments : ""
    users ||--o{ lesson_progress : ""
    users ||--o{ exercise_progress : ""
    users ||--o{ exercise_set_enrollments : ""
    roadmaps ||--o{ roadmap_enrollments : ""
    courses ||--o{ course_enrollments : ""
    lessons ||--o{ lesson_progress : ""
    exercises ||--o{ exercise_progress : ""
    exercise_sets ||--o{ exercise_set_enrollments : ""

    roadmap_enrollments {
        uuid id PK
        uuid user_id FK
        uuid roadmap_id FK
        enrollment_status status
        progression_mode mode_override "nullable learner choice"
        int completed_courses "CACHE"
        numeric progress_percent "CACHE"
        timestamptz started_at
        timestamptz completed_at
        timestamptz last_activity_at
    }
    course_enrollments {
        uuid id PK
        uuid user_id FK
        uuid course_id FK
        uuid via_roadmap_id FK "nullable"
        enrollment_status status
        int completed_lessons "CACHE"
        numeric progress_percent "CACHE"
        timestamptz started_at
        timestamptz completed_at
        timestamptz last_activity_at
    }
    lesson_progress {
        uuid user_id PK_FK
        uuid lesson_id PK_FK
        progress_status status "not_started|in_progress|completed"
        int time_spent_seconds
        int last_position_seconds "video resume"
        timestamptz completed_at
    }
    exercise_progress {
        uuid user_id PK_FK
        uuid exercise_id PK_FK
        exercise_progress_status status "todo|attempted|solved"
        int best_score
        int attempt_count
        bool is_favorite
        timestamptz first_solved_at
    }
```

### 3.1 What is persisted vs derived vs cached

| Level | Treatment | Why |
| --- | --- | --- |
| Lesson progress | **Persisted** (source of truth) | Irreducible fact — only the learner's action produces it |
| Exercise progress | **Persisted** (source of truth) | Derived from submissions, but `is_favorite` and `status` are needed without scanning submissions |
| Chapter progress | **Derived at read time** | `count(completed lessons in chapter) / count(lessons in chapter)` — cheap, always consistent, and no screen sorts or filters by it |
| Course progress | **Cached** on `course_enrollments` | Rendered on every card in every grid; recomputing across all lessons per card is O(cards × lessons). Refreshed by trigger on `lesson_progress` change |
| Roadmap progress | **Cached** on `roadmap_enrollments` | Same reason; refreshed by trigger on `course_enrollments` change |

The caches are strictly *derived values with a stated invariant*, never independently writable:

```
course_enrollments.completed_lessons
  = count(lesson_progress WHERE user=U AND status='completed' AND lesson ∈ course C)

roadmap_enrollments.completed_courses
  = count(course_enrollments WHERE user=U AND status='completed' AND course ∈ roadmap R)
```

`postgres/migrations/0012_progress_triggers.sql` maintains both, and
`scripts/verify.sql` re-derives them from scratch to assert the invariant holds.

**"Completed" is defined per level:**

| Entity | Completion condition |
| --- | --- |
| Lesson | `lesson_progress.status = 'completed'` (learner marks done / video finished) |
| Exercise | an accepted submission exists → `exercise_progress.status = 'solved'` |
| Chapter | all **non-optional** lessons in it completed |
| Course | all **non-optional** chapters completed |
| Roadmap course | that course's enrolment completed |

## 4. Collaboration

```mermaid
erDiagram
    study_groups ||--o{ group_members : ""
    study_groups ||--o{ group_role_permissions : "role defaults"
    group_members ||--o{ group_member_permissions : "per-person overrides"
    study_groups ||--o{ group_documents : ""
    study_groups ||--o{ group_exercises : "publishes"
    exercises ||--o{ group_exercises : ""
    group_exercises ||--o{ assignments : ""
    group_members ||--o{ assignments : ""
    assignments ||--o{ submissions : "versioned attempts"
    users ||--o{ submissions : ""
    exercises ||--o{ submissions : ""
    study_groups ||--o{ group_activities : ""

    study_groups {
        uuid id PK
        citext slug UK
        text name
        text description
        citext invite_code UK
        text topic
        uuid owner_id FK
        group_status status
        int member_count "CACHE"
        timestamptz last_activity_at
    }
    group_members {
        uuid id PK
        uuid group_id FK
        uuid user_id FK
        group_role role "owner|deputy|member"
        member_status status
        timestamptz joined_at
    }
    group_documents {
        uuid id PK
        uuid group_id FK
        text title
        text doc_type
        uuid uploader_id FK
        bigint size_bytes
        text storage_key
        text url
        document_status status "moderation axis"
        ai_verdict ai_verdict "AI pre-screen axis"
    }
    group_exercises {
        uuid id PK
        uuid group_id FK
        uuid exercise_id FK
        uuid assigned_by FK
        timestamptz due_at
        int attempt_limit
        bool allow_retry
        bool allow_late_submission
        text phase
        uuid reference_document_id FK
    }
    assignments {
        uuid id PK
        uuid group_exercise_id FK
        uuid member_id FK
        assignment_status status
        review_status review_status
        text feedback
        uuid reviewed_by FK
    }
    submissions {
        uuid id PK
        uuid user_id FK
        uuid exercise_id FK
        uuid assignment_id FK "nullable = practice"
        text language
        submission_verdict verdict
        int score
        int passed_tests
        int total_tests
        int runtime_ms
        int memory_kb
        text source_code
        int attempt_number
        bool is_late
        text run_detail_ref "-> mongo"
    }
```

`submissions.assignment_id` being nullable is what unifies the frontend's
`origin: "Nhóm học tập" | "Bài luyện tập"` — a group submission has an assignment, a practice
submission does not. One table, no discriminator column needed.

Permissions are two layers, matching `effectiveMemberPermissions()` exactly:
`group_role_permissions` (per group, per role) overlaid by `group_member_permissions` (per person).
Owners are not stored — they are unconditionally permitted in the resolver, as in the frontend.

## 5. Relationship rules

| Relationship | Card. | Owner | Optional | On delete parent | Unique |
| --- | --- | --- | --- | --- | --- |
| roadmap → roadmap_courses | 1:N | roadmap | — | CASCADE | (roadmap_id, course_id) |
| course → roadmap_courses | 1:N | course | — | RESTRICT | — |
| course → chapters | 1:N | course | — | CASCADE | (course_id, position) |
| chapter → lessons | 1:N | chapter | — | CASCADE | (chapter_id, position) |
| lesson → exercise | N:1 | lesson | yes | SET NULL | — |
| exercise_set → items | 1:N | set | — | CASCADE | (set_id, exercise_id) |
| user → enrolments | 1:N | user | — | CASCADE | (user_id, course_id) |
| user → lesson_progress | 1:N | user | — | CASCADE | PK (user_id, lesson_id) |
| group → members | 1:N | group | — | CASCADE | (group_id, user_id) |
| group_exercise → assignments | 1:N | group_exercise | — | CASCADE | (group_exercise_id, member_id) |
| assignment → submissions | 1:N | assignment | yes | SET NULL | (user_id, exercise_id, attempt_number) |
| all `*_prerequisites` | N:M | the gated entity | — | CASCADE | (target, source, group_index) |

**RESTRICT on `courses`** is deliberate: deleting a course that a roadmap still references should
fail loudly rather than silently reshaping someone's curriculum. Content is retired with
`status = 'archived'`, not deleted — and `0010_dependency_guards.sql` refuses to add a prerequisite
pointing at archived content.
