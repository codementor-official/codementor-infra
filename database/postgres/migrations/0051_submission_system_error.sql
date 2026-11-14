-- A submission whose grading never finished because the judge was unreachable, timed out or the
-- process died. It is not the learner's fault: it never counts toward an assignment's attempt
-- limit, never awards XP and the learner may submit again. Pending rows older than 10 minutes are
-- moved here by submission-service.
ALTER TYPE submission_verdict ADD VALUE IF NOT EXISTS 'system_error';
