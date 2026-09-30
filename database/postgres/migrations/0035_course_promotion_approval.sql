BEGIN;

CREATE TABLE IF NOT EXISTS course_promotion_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  action VARCHAR(16) NOT NULL DEFAULT 'upsert'
    CHECK (action IN ('upsert', 'remove')),
  sale_price_vnd INTEGER,
  label VARCHAR(60),
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  requested_active BOOLEAN,
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  review_reason TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT course_promotion_request_payload CHECK (
    (action = 'upsert'
      AND sale_price_vnd >= 1000
      AND char_length(trim(label)) BETWEEN 2 AND 60
      AND starts_at IS NOT NULL
      AND ends_at IS NOT NULL
      AND ends_at > starts_at
      AND requested_active IS NOT NULL)
    OR
    (action = 'remove'
      AND sale_price_vnd IS NULL
      AND label IS NULL
      AND starts_at IS NULL
      AND ends_at IS NULL
      AND requested_active IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_course_promotion_request_pending
  ON course_promotion_requests(course_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_course_promotion_requests_review_queue
  ON course_promotion_requests(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_course_promotion_requests_requester
  ON course_promotion_requests(requested_by, updated_at DESC);

COMMIT;
