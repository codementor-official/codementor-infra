-- 0016 — hạ tầng messaging dùng chung cho mọi service.
--
-- Hai bảng này KHÔNG thuộc bounded context nào — chúng là hạ tầng, giống như bảng
-- migration history. Mọi service đều được ghi vào chúng.

BEGIN;

-- ---------------------------------------------------------------------------
-- Transactional outbox
--
-- Ghi message vào đây TRONG CÙNG transaction với dữ liệu nghiệp vụ, một poller đẩy
-- lên Kafka sau. Giải quyết trường hợp tiến trình chết giữa "commit DB" và "send Kafka"
-- khiến message mất vĩnh viễn (bài nộp treo mãi ở trạng thái pending).
-- ---------------------------------------------------------------------------
CREATE TABLE outbox (
  id            uuid PRIMARY KEY,          -- chính là eventId trong envelope
  topic         text NOT NULL,
  partition_key text,                      -- NULL = Kafka phân phối round-robin
  payload       jsonb NOT NULL,            -- toàn bộ EventEnvelope
  created_at    timestamptz NOT NULL DEFAULT now(),
  published_at  timestamptz,               -- NULL = chưa gửi

  CONSTRAINT outbox_topic_not_blank CHECK (btrim(topic) <> '')
);

-- Poller chỉ quét hàng chưa gửi. Partial index giữ index nhỏ ngay cả khi bảng lớn dần.
CREATE INDEX idx_outbox_pending ON outbox (created_at) WHERE published_at IS NULL;

COMMENT ON TABLE outbox IS
  'Transactional outbox. Hàng đã published_at có thể dọn định kỳ sau vài ngày.';

-- ---------------------------------------------------------------------------
-- Khử trùng lặp phía consumer
--
-- Kafka đảm bảo at-least-once: message sẽ được giao lại khi consumer restart hoặc
-- rebalance. Không có bảng này thì "cộng 50 XP" chạy hai lần là chuyện sớm muộn.
--
-- Khoá chính gồm cả `consumer` vì nhiều service cùng nghe một event và mỗi service
-- phải xử lý đúng một lần — không phải chỉ một service được xử lý.
-- ---------------------------------------------------------------------------
CREATE TABLE processed_events (
  consumer     text NOT NULL,              -- tên consumer group, vd 'core-service'
  event_id     uuid NOT NULL,              -- envelope.eventId
  topic        text NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (consumer, event_id)
);

-- Phục vụ dọn dẹp định kỳ các bản ghi cũ.
CREATE INDEX idx_processed_events_time ON processed_events (processed_at);

COMMENT ON TABLE processed_events IS
  'Chống xử lý trùng. Có thể xoá bản ghi cũ hơn thời gian retention của Kafka.';

COMMIT;
