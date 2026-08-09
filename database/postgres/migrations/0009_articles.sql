-- 0009 — editorial articles (/articles, /articles/[slug]).
-- Spine here, variable-shape body (sections[]) in MongoDB article_contents.

BEGIN;

CREATE TABLE articles (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug         citext NOT NULL UNIQUE,
  title        text   NOT NULL,
  excerpt      text,
  takeaway     text,
  -- Article.author + Article.role were free strings; the author is a real account and the
  -- role is their platform title, not a per-article attribute.
  author_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  tag_id       uuid REFERENCES tags(id)  ON DELETE SET NULL,
  read_minutes integer CHECK (read_minutes IS NULL OR read_minutes > 0),
  status       content_status NOT NULL DEFAULT 'draft',
  content_ref  text,                       -- MongoDB article_contents._id
  published_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT articles_published_needs_date_and_body
    CHECK (status <> 'published' OR (published_at IS NOT NULL AND content_ref IS NOT NULL))
);

CREATE TRIGGER trg_articles_touch BEFORE UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

COMMIT;
