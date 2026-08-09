-- 0003 — shared vocabularies.
-- The frontend repeats the same concepts as free strings across files with inconsistent
-- spellings ("C/C++" vs "C++", "Spring Boot" vs "Spring"). Filters built on those strings
-- are silently wrong. Normalised here so every surface filters on the same rows.

BEGIN;

CREATE TABLE technologies (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug       citext NOT NULL UNIQUE,
  name       text   NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT technologies_name_not_blank CHECK (btrim(name) <> '')
);

COMMENT ON TABLE technologies IS 'Shared by roadmaps, courses, exercises and learner preferences — the join target that makes technology filters reliable.';

CREATE TABLE tags (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug       citext NOT NULL UNIQUE,
  name       text   NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE tags IS 'Free-form topical labels for exercises and articles ("Mảng", "Thuật toán", "DOM").';

-- Companies an exercise is "commonly asked at" — the practice page's interview-prep angle
-- ("Nhu cầu tuyển dụng"). A distinct vocabulary from tags: these are organisations, and the
-- product surfaces them separately.
CREATE TABLE companies (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug       citext NOT NULL UNIQUE,
  name       text   NOT NULL,
  logo_url   text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMIT;
