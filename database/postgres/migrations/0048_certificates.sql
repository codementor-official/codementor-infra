-- 0048 — completion certificates (backend ADR 0005, phase 2).
--
-- Lecturers design templates; a course or roadmap may point at one. With no template the
-- platform default applies, so every course and roadmap issues a certificate. A learner claims
-- it once per course/roadmap: the certificate keeps a SNAPSHOT of the design and data at issue
-- time, so editing the template or renaming the course later never changes an issued one.
--
-- Additive only: new enum, two new tables, two nullable columns. Nothing existing reads them.
BEGIN;

CREATE TYPE certificate_subject AS ENUM ('course', 'roadmap');

CREATE TABLE certificate_templates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL = the platform default, editable by admins only (`owns()` in libs/platform).
  owner_id    uuid REFERENCES users(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 80),
  -- NULL = usable for both courses and roadmaps.
  subject     certificate_subject,
  -- Shape and rules: learning-service `certificate-design.ts` (validated there, not here).
  design      jsonb NOT NULL CHECK (jsonb_typeof(design) = 'object'),
  archived_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Exactly one platform default.
CREATE UNIQUE INDEX certificate_templates_one_default
  ON certificate_templates ((owner_id IS NULL)) WHERE owner_id IS NULL;
CREATE INDEX certificate_templates_owner ON certificate_templates (owner_id) WHERE archived_at IS NULL;

ALTER TABLE courses
  ADD COLUMN IF NOT EXISTS certificate_template_id uuid
    REFERENCES certificate_templates(id) ON DELETE SET NULL;
ALTER TABLE roadmaps
  ADD COLUMN IF NOT EXISTS certificate_template_id uuid
    REFERENCES certificate_templates(id) ON DELETE SET NULL;

CREATE TABLE certificates (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Public verification code, e.g. "K7Q2M9XD3F". Unguessable (~50 bits), not sequential.
  code           text NOT NULL UNIQUE CHECK (code ~ '^[0-9A-Z]{10}$'),
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subject        certificate_subject NOT NULL,
  -- Course or roadmap id. No FK (two possible parents); the snapshot keeps the certificate
  -- readable even if the course is later deleted.
  subject_id     uuid NOT NULL,
  template_id    uuid REFERENCES certificate_templates(id) ON DELETE SET NULL,
  recipient_name text NOT NULL CHECK (char_length(recipient_name) BETWEEN 2 AND 80),
  data           jsonb NOT NULL CHECK (jsonb_typeof(data) = 'object'),
  design         jsonb NOT NULL CHECK (jsonb_typeof(design) = 'object'),
  issued_at      timestamptz NOT NULL DEFAULT now(),
  revoked_at     timestamptz,
  revoked_by     uuid REFERENCES users(id) ON DELETE SET NULL,
  revoke_reason  text,
  CONSTRAINT certificates_revoke_consistency CHECK (
    (revoked_at IS NULL) = (revoke_reason IS NULL)
  )
);

-- "One certificate per learner per course/roadmap" is this index, not application code: two
-- tabs confirming at once get one row and one unique violation (409). A revoked certificate
-- frees the slot so an admin-approved correction can be claimed again.
CREATE UNIQUE INDEX certificates_one_active
  ON certificates (user_id, subject, subject_id) WHERE revoked_at IS NULL;
CREATE INDEX certificates_subject ON certificates (subject, subject_id) WHERE revoked_at IS NULL;
CREATE INDEX certificates_issued_at ON certificates (issued_at DESC);

INSERT INTO certificate_templates (owner_id, name, subject, design) VALUES (
  NULL,
  'Mẫu mặc định CodeMentor',
  NULL,
  '{
    "version": 1,
    "layout": "classic",
    "accent": "orange",
    "heading": "Chứng nhận hoàn thành",
    "body": "Đã hoàn thành {{subjectKind}} “{{subjectTitle}}” trên nền tảng CodeMentor.",
    "signerName": "{{instructorName}}",
    "signerTitle": "Giảng viên",
    "fields": [
      { "label": "Ngày hoàn thành", "value": "{{completedAt}}" },
      { "label": "Thời lượng", "value": "{{durationHours}} giờ" },
      { "label": "Mã chứng chỉ", "value": "{{certificateCode}}" }
    ]
  }'::jsonb
);

COMMIT;
