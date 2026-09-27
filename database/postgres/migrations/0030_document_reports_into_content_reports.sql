-- 0030 — báo cáo tài liệu nhóm dồn về `content_reports`.
--
-- `workspace_document_reports` được ghi nhưng không màn hình hay API nào đọc: báo cáo của học
-- viên rơi vào hư không. Từ bản workspace-service đi kèm migration này, báo cáo tài liệu ghi
-- thẳng `content_reports` (target_type = 'DOCUMENT') và hiện ở trang Báo cáo vi phạm của admin.
--
-- CHẠY SAU KHI workspace-service mới đã deploy. Bản cũ còn ghi vào bảng bị xoá ở đây, nên chạy
-- sớm là báo cáo tài liệu trả 500 cho tới lúc deploy.
--
-- Bộ lý do cũ có hai giá trị không có trong `content_reports` (`harmful`, `irrelevant`): gộp về
-- INAPPROPRIATE / OTHER và giữ nhãn gốc ở đầu ghi chú để admin không mất thông tin.

-- `workspace_document_reports` do `codementor-backend/scripts/migrate-workspace-content.mjs` tạo,
-- không phải migration nào ở đây — một DB dựng mới chỉ từ repo này không có nó. Khi đó không có
-- gì để chép, và `DROP TABLE IF EXISTS` là đủ.

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.workspace_document_reports') IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO content_reports
    (reporter_id, target_type, target_id, target_ref, category, note, status, created_at, updated_at)
  SELECT
    r.reporter_id,
    'DOCUMENT',
    r.document_id,
    left(d.title || ' · /workspace/' || g.slug, 240),
    CASE r.category
      WHEN 'spam' THEN 'SPAM'
      WHEN 'copyright' THEN 'COPYRIGHT'
      WHEN 'inappropriate' THEN 'INAPPROPRIATE'
      WHEN 'harmful' THEN 'INAPPROPRIATE'
      ELSE 'OTHER'
    END,
    CASE r.category
      WHEN 'harmful' THEN left('[Nội dung có hại] ' || coalesce(r.note, ''), 1000)
      WHEN 'irrelevant' THEN left('[Không liên quan nhóm] ' || coalesce(r.note, ''), 1000)
      ELSE r.note
    END,
    CASE WHEN r.status IN ('PENDING', 'RESOLVED', 'REJECTED') THEN r.status ELSE 'PENDING' END,
    r.created_at,
    r.updated_at
  FROM workspace_document_reports r
  JOIN group_documents d ON d.id = r.document_id
  JOIN study_groups g ON g.id = r.group_id
  -- Người đó đã báo cáo tài liệu này qua đường mới: bản mới hơn thắng.
  ON CONFLICT (reporter_id, target_type, target_id) DO NOTHING;
END $$;

DROP TABLE IF EXISTS workspace_document_reports;

COMMIT;
