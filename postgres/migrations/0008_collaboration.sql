-- 0008 — study groups, documents, group-published exercises, assignments, submissions.

BEGIN;

CREATE TABLE study_groups (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug             citext NOT NULL UNIQUE,          -- /workspace/[groupId]
  name             text   NOT NULL,
  description      text,
  invite_code      citext NOT NULL UNIQUE,          -- "tham gia bằng mã"
  topic            text,
  owner_id         uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status           group_status NOT NULL DEFAULT 'active',
  member_count     integer NOT NULL DEFAULT 0 CHECK (member_count >= 0),   -- CACHE
  last_activity_at timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT study_groups_invite_code_format CHECK (invite_code ~ '^[A-Za-z0-9]{5,12}$')
);

CREATE TRIGGER trg_study_groups_touch BEFORE UPDATE ON study_groups
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Exercises may be owned by a group (private) or by the public catalogue (NULL).
ALTER TABLE exercises
  ADD CONSTRAINT exercises_owner_group_id_fkey
  FOREIGN KEY (owner_group_id) REFERENCES study_groups(id) ON DELETE CASCADE;

CREATE TABLE group_members (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id  uuid NOT NULL REFERENCES study_groups(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES users(id)        ON DELETE CASCADE,
  role      group_role    NOT NULL DEFAULT 'member',
  status    member_status NOT NULL DEFAULT 'active',
  joined_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (group_id, user_id),
  -- Composite-unique target so assignments can prove a member belongs to the right group.
  CONSTRAINT group_members_id_group_unique UNIQUE (group_id, id)
);

-- Exactly one owner per group.
CREATE UNIQUE INDEX uq_group_members_single_owner
  ON group_members (group_id) WHERE role = 'owner';

-- ---------------------------------------------------------------------------
-- Permissions — two layers, mirroring effectiveMemberPermissions() in the frontend.
-- Owners are NOT stored: they are unconditionally permitted by the resolver.
-- ---------------------------------------------------------------------------
CREATE TABLE group_role_permissions (
  group_id   uuid NOT NULL REFERENCES study_groups(id) ON DELETE CASCADE,
  role       group_role       NOT NULL,
  permission group_permission NOT NULL,
  allowed    boolean NOT NULL DEFAULT false,

  PRIMARY KEY (group_id, role, permission),
  -- Owner permissions are implicit; storing them invites drift.
  CONSTRAINT grp_configurable_roles_only CHECK (role <> 'owner')
);

CREATE TABLE group_member_permissions (
  group_member_id uuid NOT NULL REFERENCES group_members(id) ON DELETE CASCADE,
  permission      group_permission NOT NULL,
  allowed         boolean NOT NULL,
  PRIMARY KEY (group_member_id, permission)
);

COMMENT ON TABLE group_member_permissions IS 'Per-person overrides layered over group_role_permissions. Two members of the same role may legitimately differ.';

-- ---------------------------------------------------------------------------
-- Documents. status (human moderation) and ai_verdict (automated pre-screen) are two
-- INDEPENDENT axes — the frontend keeps both and so do we.
-- ---------------------------------------------------------------------------
CREATE TABLE group_documents (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES study_groups(id) ON DELETE CASCADE,
  title       text NOT NULL,
  doc_type    text NOT NULL,                    -- PDF | Slide | Video | Link
  topic       text,
  uploader_id uuid REFERENCES users(id) ON DELETE SET NULL,
  size_bytes  bigint CHECK (size_bytes IS NULL OR size_bytes >= 0),
  storage_key text,                             -- object-store key for uploaded files
  url         text,                             -- target for doc_type='Link'
  preview_text text,
  status      document_status NOT NULL DEFAULT 'pending',
  ai_verdict  ai_verdict      NOT NULL DEFAULT 'valid',
  reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  uploaded_at timestamptz NOT NULL DEFAULT now(),

  -- A link document needs a URL; an uploaded one needs somewhere to read the bytes from.
  CONSTRAINT group_documents_body_present
    CHECK ((doc_type = 'Link' AND url IS NOT NULL) OR (doc_type <> 'Link' AND storage_key IS NOT NULL))
);

-- ---------------------------------------------------------------------------
-- Publishing an exercise into a group. Separate from `exercises` because the deadline,
-- attempt policy and teaching phase belong to THIS group's use of it — the same exercise
-- can be published to several groups with different rules.
-- ---------------------------------------------------------------------------
CREATE TABLE group_exercises (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id               uuid NOT NULL REFERENCES study_groups(id) ON DELETE CASCADE,
  exercise_id            uuid NOT NULL REFERENCES exercises(id)    ON DELETE CASCADE,
  assigned_by            uuid REFERENCES users(id) ON DELETE SET NULL,
  due_at                 timestamptz,
  attempt_limit          integer CHECK (attempt_limit IS NULL OR attempt_limit > 0),
  allow_retry            boolean NOT NULL DEFAULT true,
  allow_late_submission  boolean NOT NULL DEFAULT false,
  phase                  text,                                     -- teaching phase label
  reference_document_id  uuid REFERENCES group_documents(id) ON DELETE SET NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),

  UNIQUE (group_id, exercise_id),
  CONSTRAINT group_exercises_id_group_unique UNIQUE (group_id, id)
);

-- ---------------------------------------------------------------------------
-- Assignment = one member's obligation for one published exercise.
-- ---------------------------------------------------------------------------
CREATE TABLE assignments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid NOT NULL,
  group_exercise_id uuid NOT NULL,
  member_id         uuid NOT NULL,
  status            assignment_status NOT NULL DEFAULT 'notstarted',
  review_status     review_status     NOT NULL DEFAULT 'pending',
  feedback          text,
  started_at        timestamptz,
  reviewed_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  UNIQUE (group_exercise_id, member_id),

  -- Both endpoints must belong to the SAME group — declaratively, no trigger.
  CONSTRAINT assignments_exercise_in_group FOREIGN KEY (group_id, group_exercise_id)
    REFERENCES group_exercises (group_id, id) ON DELETE CASCADE,
  CONSTRAINT assignments_member_in_group FOREIGN KEY (group_id, member_id)
    REFERENCES group_members (group_id, id) ON DELETE CASCADE,

  CONSTRAINT assignments_reviewed_consistency
    CHECK ((review_status = 'pending') = (reviewed_at IS NULL))
);

CREATE TRIGGER trg_assignments_touch BEFORE UPDATE ON assignments
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Submissions. One table for both origins the frontend distinguishes as
-- "Nhóm học tập" vs "Bài luyện tập": a group submission has an assignment_id, a practice
-- submission does not. No discriminator column needed.
-- ---------------------------------------------------------------------------
CREATE TABLE submissions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id)     ON DELETE CASCADE,
  exercise_id    uuid NOT NULL REFERENCES exercises(id) ON DELETE RESTRICT,
  assignment_id  uuid REFERENCES assignments(id) ON DELETE SET NULL,

  language       text NOT NULL,
  source_code    text NOT NULL,
  verdict        submission_verdict NOT NULL DEFAULT 'pending',
  score          integer CHECK (score IS NULL OR score BETWEEN 0 AND 100),
  passed_tests   integer CHECK (passed_tests IS NULL OR passed_tests >= 0),
  total_tests    integer CHECK (total_tests  IS NULL OR total_tests  >= 0),
  runtime_ms     integer CHECK (runtime_ms IS NULL OR runtime_ms >= 0),
  memory_kb      integer CHECK (memory_kb  IS NULL OR memory_kb  >= 0),

  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  is_late        boolean NOT NULL DEFAULT false,
  note           text,
  -- MongoDB submission_run_details._id — bulky per-test output lives there.
  run_detail_ref text,
  submitted_at   timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, exercise_id, attempt_number),
  CONSTRAINT submissions_passed_le_total
    CHECK (passed_tests IS NULL OR total_tests IS NULL OR passed_tests <= total_tests)
);

COMMENT ON COLUMN submissions.assignment_id IS 'NULL = free practice submission; set = submitted against a study-group assignment. This is what unifies SubmissionOrigin from the frontend.';

-- ---------------------------------------------------------------------------
-- Activity feed
-- ---------------------------------------------------------------------------
CREATE TABLE group_activities (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES study_groups(id) ON DELETE CASCADE,
  actor_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  action      text NOT NULL,
  target_type text,
  target_id   uuid,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMIT;
