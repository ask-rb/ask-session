# frozen_string_literal: true

require_relative "test_helper"

class StateTest < Minitest::Test
  include TestHelpers

  def test_reduce_empty_events_returns_default_record
    record = Ask::Session::State.reduce("s1", [])
    assert_equal "s1", record.id
    assert_equal :active, record.status
  end

  def test_reduce_session_created
    event = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active, metadata: { key: "val" } })
    record = Ask::Session::State.reduce("s1", [event])

    assert_equal "s1", record.id
    assert_equal :active, record.status
    assert_equal({ key: "val" }, record.metadata)
    assert_equal 1, record.version
  end

  def test_reduce_status_changed
    e1 = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active })
    e2 = build_event(session_id: "s1", seq: 2, type: "session.status_changed",
      payload: { status: :completed })
    record = Ask::Session::State.reduce("s1", [e1, e2])

    assert_equal :completed, record.status
    assert_equal 2, record.version
  end

  def test_reduce_message_added
    e1 = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active })
    e2 = build_event(session_id: "s1", seq: 2, type: "message.added",
      payload: { role: :user, content: "hello" })
    record = Ask::Session::State.reduce("s1", [e1, e2])

    assert_equal :active, record.status
    assert_equal 2, record.version
  end

  def test_reduce_tool_completed
    e1 = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active })
    e2 = build_event(session_id: "s1", seq: 2, type: "tool.completed",
      payload: { tool: "search", result: "ok" })
    record = Ask::Session::State.reduce("s1", [e1, e2])

    assert_equal :active, record.status
    assert_equal 2, record.version
  end

  def test_reduce_unknown_event_preserved
    e1 = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active })
    e2 = build_event(session_id: "s1", seq: 2, type: "unknown.event",
      payload: { data: "whatever" })
    e3 = build_event(session_id: "s1", seq: 3, type: "message.added",
      payload: { role: :user, content: "hi" })

    record = Ask::Session::State.reduce("s1", [e1, e2, e3])
    assert_equal :active, record.status
    assert_equal 3, record.version
  end

  def test_reduce_preserves_created_at
    now = Time.utc(2026, 3, 15)
    event = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active }, created_at: now)
    record = Ask::Session::State.reduce("s1", [event])

    assert_equal now, record.created_at
    assert_equal now, record.updated_at
  end

  def test_reduce_updates_updated_at
    t1 = Time.utc(2026, 3, 15)
    t2 = Time.utc(2026, 3, 16)
    e1 = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active }, created_at: t1)
    e2 = build_event(session_id: "s1", seq: 2, type: "message.added",
      payload: {}, created_at: t2)
    record = Ask::Session::State.reduce("s1", [e1, e2])

    assert_equal t1, record.created_at
    assert_equal t2, record.updated_at
  end

  def test_reduce_unknown_event_advances_version_and_updated_at
    t1 = Time.utc(2026, 3, 15)
    t2 = Time.utc(2026, 3, 16)
    e1 = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active }, created_at: t1)
    e2 = build_event(session_id: "s1", seq: 2, type: "vendor.custom.event",
      payload: { data: "x" }, created_at: t2)

    record = Ask::Session::State.reduce("s1", [e1, e2])
    assert_equal :active, record.status
    assert_equal 2, record.version
    assert_equal t2, record.updated_at
  end

  def test_reduce_unknown_event_without_session_created_raises
    e1 = build_event(session_id: "s1", seq: 1, type: "vendor.unknown",
      payload: {})

    assert_raises(RuntimeError) { Ask::Session::State.reduce("s1", [e1]) }
  end
end
