-- 0013 — indexes.
--
-- Only indexes justified by a query the frontend actually issues. Primary keys and UNIQUE
-- constraints already provide their own; those are not duplicated here.
--
-- Note on the edge tables: their PK is (target, source, group_index), which serves
-- "what does X depend on?". The reverse question — "what does completing X unlock?" — needs
-- an index leading with source, added below.

BEGIN;

-- ---------------------------------------------------------------------------
-- Browse / filter (Explore, Lộ trình học, Practice)
-- ---------------------------------------------------------------------------
CREATE INDEX idx_roadmaps_browse
  ON roadmaps (field, level, popularity_score DESC)
  WHERE status = 'published';

CREATE INDEX idx_courses_browse
  ON courses (level, status) WHERE status = 'published';

CREATE INDEX idx_courses_instructor ON courses (instructor_id) WHERE instructor_id IS NOT NULL;

CREATE INDEX idx_exercises_browse
  ON exercises (difficulty, status) WHERE status = 'published' AND owner_group_id IS NULL;

CREATE INDEX idx_exercises_group ON exercises (owner_group_id) WHERE owner_group_id IS NOT NULL;
CREATE INDEX idx_exercises_author ON exercises (author_id) WHERE author_id IS NOT NULL;

-- Tag/technology facets are read right-to-left as often as left-to-right.
CREATE INDEX idx_exercise_tags_tag                 ON exercise_tags (tag_id);
CREATE INDEX idx_exercise_technologies_technology  ON exercise_technologies (technology_id);
CREATE INDEX idx_course_technologies_technology    ON course_technologies (technology_id);
CREATE INDEX idx_roadmap_technologies_technology   ON roadmap_technologies (technology_id);
CREATE INDEX idx_exercise_companies_company        ON exercise_companies (company_id);

-- ---------------------------------------------------------------------------
-- Curriculum traversal
-- ---------------------------------------------------------------------------
CREATE INDEX idx_chapters_course_position ON chapters (course_id, position);
CREATE INDEX idx_lessons_chapter_position ON lessons (chapter_id, position);
-- fn_lesson_available / fn_refresh_course_progress scan by course.
CREATE INDEX idx_lessons_course           ON lessons (course_id);
CREATE INDEX idx_lessons_exercise         ON lessons (exercise_id) WHERE exercise_id IS NOT NULL;
CREATE INDEX idx_roadmap_courses_roadmap  ON roadmap_courses (roadmap_id, position);
CREATE INDEX idx_roadmap_courses_course   ON roadmap_courses (course_id);

-- ---------------------------------------------------------------------------
-- Dependency graph — reverse direction ("what does finishing X unlock?")
-- ---------------------------------------------------------------------------
CREATE INDEX idx_rcp_source ON roadmap_course_prerequisites (source_roadmap_course_id);
CREATE INDEX idx_cp_source  ON course_prerequisites         (source_course_id);
CREATE INDEX idx_chp_source ON chapter_prerequisites        (source_chapter_id);
CREATE INDEX idx_lp_source  ON lesson_prerequisites         (source_lesson_id);
CREATE INDEX idx_ep_source  ON exercise_prerequisites       (set_id, source_exercise_id);

-- The cycle-detection trigger walks forward from the target within one scope.
CREATE INDEX idx_lp_course  ON lesson_prerequisites  (course_id);
CREATE INDEX idx_chp_course ON chapter_prerequisites (course_id);

-- ---------------------------------------------------------------------------
-- Learner state (dashboard, progress, continue-learning)
-- ---------------------------------------------------------------------------
CREATE INDEX idx_course_enrollments_user
  ON course_enrollments (user_id, last_activity_at DESC NULLS LAST);
CREATE INDEX idx_course_enrollments_course ON course_enrollments (course_id);
CREATE INDEX idx_roadmap_enrollments_user
  ON roadmap_enrollments (user_id, last_activity_at DESC NULLS LAST);

CREATE INDEX idx_lesson_progress_lesson ON lesson_progress (lesson_id);
-- "resume where I left off"
CREATE INDEX idx_lesson_progress_active
  ON lesson_progress (user_id, updated_at DESC) WHERE status = 'in_progress';

CREATE INDEX idx_exercise_progress_exercise ON exercise_progress (exercise_id);
CREATE INDEX idx_exercise_progress_favorite
  ON exercise_progress (user_id) WHERE is_favorite;
CREATE INDEX idx_exercise_progress_solved
  ON exercise_progress (user_id, first_solved_at DESC) WHERE status = 'solved';

-- ---------------------------------------------------------------------------
-- Submissions (history tab, group review queue)
-- ---------------------------------------------------------------------------
CREATE INDEX idx_submissions_user_recent ON submissions (user_id, submitted_at DESC);
CREATE INDEX idx_submissions_exercise    ON submissions (exercise_id, submitted_at DESC);
CREATE INDEX idx_submissions_assignment  ON submissions (assignment_id) WHERE assignment_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Study groups
-- ---------------------------------------------------------------------------
CREATE INDEX idx_group_members_user   ON group_members (user_id) WHERE status = 'active';
CREATE INDEX idx_group_documents_group ON group_documents (group_id, uploaded_at DESC);
-- moderation queue
CREATE INDEX idx_group_documents_pending
  ON group_documents (group_id) WHERE status IN ('pending', 'changes');
CREATE INDEX idx_group_exercises_group ON group_exercises (group_id, due_at NULLS LAST);
CREATE INDEX idx_assignments_member    ON assignments (member_id, status);
-- review queue
CREATE INDEX idx_assignments_review
  ON assignments (group_id) WHERE review_status = 'pending';
CREATE INDEX idx_group_activities_group ON group_activities (group_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Articles
-- ---------------------------------------------------------------------------
CREATE INDEX idx_articles_published
  ON articles (published_at DESC) WHERE status = 'published';
CREATE INDEX idx_articles_tag ON articles (tag_id) WHERE tag_id IS NOT NULL;

COMMIT;
