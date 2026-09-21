# frozen_string_literal: true

require_relative "test_helper"

class RecordSerializationTest < Minitest::Test
  include TestHelpers

  def test_to_h_preserves_fields
    record = build_record(id: "s1", status: :active, version: 3,
      metadata: { nested: { key: "val" } })
    h = record.to_h

    assert_equal "s1", h[:id]
    assert_equal :active, h[:status]
    assert_equal 3, h[:version]
    assert_equal({ nested: { key: "val" } }, h[:metadata])
  end

  def test_to_h_timestamps_are_iso8601
    record = build_record(
      created_at: Time.utc(2026, 7, 4, 12, 30, 0),
      updated_at: Time.utc(2026, 7, 5, 8, 0, 0)
    )
    h = record.to_h

    assert_kind_of String, h[:created_at]
    assert_kind_of String, h[:updated_at]
    assert h[:created_at].end_with?("Z"), "created_at must be ISO8601 UTC"
    assert h[:updated_at].end_with?("Z"), "updated_at must be ISO8601 UTC"
  end

  def test_from_h_restores_record
    now = Time.utc(2026, 1, 1)
    h = { id: "s1", status: :active, metadata: { a: 1 },
          created_at: now.iso8601, updated_at: now.iso8601, version: 2 }
    record = Ask::Session::Record.from_h(h)

    assert_equal "s1", record.id
    assert_equal :active, record.status
    assert_equal({ a: 1 }, record.metadata)
    assert_equal 2, record.version
    assert_instance_of Time, record.created_at
  end

  def test_round_trip_preserves_nested_metadata
    original = build_record(
      metadata: { level1: { level2: [1, 2, { three: "deep" }] } }
    )
    restored = Ask::Session::Record.from_h(original.to_h)

    assert_equal original.id, restored.id
    assert_equal original.status, restored.status
    assert_equal original.metadata, restored.metadata
    assert_equal original.version, restored.version
  end

  def test_round_trip_preserves_iso8601_timestamps
    created = Time.utc(2026, 6, 15, 10, 30, 45)
    updated = Time.utc(2026, 6, 16, 14, 0, 0)
    original = build_record(created_at: created, updated_at: updated)
    h = original.to_h

    restored = Ask::Session::Record.from_h(h)
    assert_equal created, restored.created_at
    assert_equal updated, restored.updated_at
  end

  def test_to_h_has_string_keys
    record = build_record
    json = JSON.generate(record.to_h)
    parsed = JSON.parse(json)

    assert parsed.key?("id"), "JSON must have string key 'id'"
    assert parsed.key?("status"), "JSON must have string key 'status'"
    assert parsed.key?("metadata"), "JSON must have string key 'metadata'"
    assert parsed.key?("version"), "JSON must have string key 'version'"
    assert parsed.key?("created_at"), "JSON must have string key 'created_at'"
    assert parsed.key?("updated_at"), "JSON must have string key 'updated_at'"
  end
end

class EventSerializationTest < Minitest::Test
  include TestHelpers

  def test_to_h_preserves_fields
    event = build_event(session_id: "s1", seq: 5, type: "msg.added",
      payload: { nested: { key: "val" } }, trace_id: "t1",
      causation_id: "c1")
    h = event.to_h

    assert_equal "s1", h[:session_id]
    assert_equal 5, h[:seq]
    assert_equal "msg.added", h[:type]
    assert_equal({ nested: { key: "val" } }, h[:payload])
    assert_equal "t1", h[:trace_id]
    assert_equal "c1", h[:causation_id]
  end

  def test_to_h_timestamp_is_iso8601
    event = build_event(created_at: Time.utc(2026, 3, 10, 9, 0, 0))
    h = event.to_h

    assert_kind_of String, h[:created_at]
    assert h[:created_at].end_with?("Z"), "created_at must be ISO8601 UTC"
  end

  def test_from_h_restores_event
    now = Time.utc(2026, 1, 1)
    h = { session_id: "s1", seq: 1, type: "session.created",
          payload: { status: :active }, trace_id: "t1",
          causation_id: nil, created_at: now.iso8601 }
    event = Ask::Session::Event.from_h(h)

    assert_equal "s1", event.session_id
    assert_equal 1, event.seq
    assert_equal "session.created", event.type
    assert_equal({ status: :active }, event.payload)
    assert_equal "t1", event.trace_id
    assert_nil event.causation_id
    assert_instance_of Time, event.created_at
  end

  def test_round_trip_preserves_nested_payload
    original = build_event(
      payload: { level1: { level2: [1, 2, { three: "deep" }] } }
    )
    restored = Ask::Session::Event.from_h(original.to_h)

    assert_equal original.session_id, restored.session_id
    assert_equal original.seq, restored.seq
    assert_equal original.type, restored.type
    assert_equal original.payload, restored.payload
    assert_equal original.trace_id, restored.trace_id
  end

  def test_round_trip_preserves_causation_id
    original = build_event(causation_id: "evt_prev_123")
    restored = Ask::Session::Event.from_h(original.to_h)

    assert_equal "evt_prev_123", restored.causation_id
  end

  def test_round_trip_preserves_iso8601_timestamp
    created = Time.utc(2026, 8, 1, 15, 30, 0)
    original = build_event(created_at: created)
    h = original.to_h

    restored = Ask::Session::Event.from_h(h)
    assert_equal created, restored.created_at
  end

  def test_to_h_has_string_keys
    event = build_event
    json = JSON.generate(event.to_h)
    parsed = JSON.parse(json)

    assert parsed.key?("session_id"), "JSON must have string key 'session_id'"
    assert parsed.key?("seq"), "JSON must have string key 'seq'"
    assert parsed.key?("type"), "JSON must have string key 'type'"
    assert parsed.key?("payload"), "JSON must have string key 'payload'"
    assert parsed.key?("trace_id"), "JSON must have string key 'trace_id'"
    assert parsed.key?("causation_id"), "JSON must have string key 'causation_id'"
    assert parsed.key?("created_at"), "JSON must have string key 'created_at'"
  end
end

class CodecRecordTest < Minitest::Test
  include TestHelpers

  def test_dump_record_returns_json_string
    record = build_record
    json = Ask::Session::Codec.dump_record(record)

    assert_kind_of String, json
    assert JSON.parse(json).key?("id")
  end

  def test_load_record_restores_from_json
    record = build_record(id: "s1", status: :completed, version: 5,
      metadata: { nested: { deep: true } })
    json = Ask::Session::Codec.dump_record(record)
    restored = Ask::Session::Codec.load_record(json)

    assert_equal "s1", restored.id
    assert_equal :completed, restored.status
    assert_equal 5, restored.version
    assert_equal({ nested: { deep: true } }, restored.metadata)
  end

  def test_load_record_raises_on_malformed_json
    assert_raises(Ask::Session::SerializationError) do
      Ask::Session::Codec.load_record("{invalid json!!!")
    end
  end

  def test_load_record_raises_on_missing_required_field
    assert_raises(Ask::Session::SerializationError) do
      Ask::Session::Codec.load_record('{"status":"active"}')
    end
  end
end

class CodecEventTest < Minitest::Test
  include TestHelpers

  def test_dump_event_returns_json_string
    event = build_event
    json = Ask::Session::Codec.dump_event(event)

    assert_kind_of String, json
    assert JSON.parse(json).key?("session_id")
  end

  def test_load_event_restores_from_json
    event = build_event(session_id: "s1", seq: 3, type: "msg.added",
      payload: { text: "hello" }, trace_id: "t1",
      causation_id: "c1")
    json = Ask::Session::Codec.dump_event(event)
    restored = Ask::Session::Codec.load_event(json)

    assert_equal "s1", restored.session_id
    assert_equal 3, restored.seq
    assert_equal "msg.added", restored.type
    assert_equal({ text: "hello" }, restored.payload)
    assert_equal "t1", restored.trace_id
    assert_equal "c1", restored.causation_id
  end

  def test_load_event_raises_on_malformed_json
    assert_raises(Ask::Session::SerializationError) do
      Ask::Session::Codec.load_event("not json at all")
    end
  end

  def test_load_event_raises_on_missing_required_field
    assert_raises(Ask::Session::SerializationError) do
      Ask::Session::Codec.load_event('{"seq":1}')
    end
  end

  def test_load_event_raises_on_nil_type
    assert_raises(Ask::Session::SerializationError) do
      Ask::Session::Codec.load_event('{"session_id":"s1","seq":1,"type":null}')
    end
  end
end
