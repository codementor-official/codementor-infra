BEGIN;

CREATE TABLE IF NOT EXISTS course_promotions (
  course_id UUID PRIMARY KEY REFERENCES courses(id) ON DELETE CASCADE,
  sale_price_vnd INTEGER NOT NULL CHECK (sale_price_vnd >= 1000),
  label VARCHAR(60) NOT NULL CHECK (char_length(trim(label)) BETWEEN 2 AND 60),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT course_promotions_time_range CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_course_promotions_active_window
  ON course_promotions(is_active, starts_at, ends_at);

COMMIT;
