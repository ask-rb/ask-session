# frozen_string_literal: true

require_relative "test_helper"

class EventTest < Minitest::Test
  include TestHelpers

  def test_event_is_immutable
    event = build_event
    assert_instance_of Ask::Session::Event, event
    assert_equal "sess_001", event.session_id
    assert_equal 1, event.seq
    assert_equal "session.created", event.type
    assert_equal({}, event.payload)
  end

  def test_event_create_with_defaults
    event = Ask::Session::Event.create(session_id: "s1", seq: 1, type: "test.event")
    assert_equal "s1", event.session_id
    assert event.trace_id.start_with?("trace_")
    assert_nil event.causation_id
  end

  def test_event_create_with_explicit_fields
    event = Ask::Session::Event.create(
      session_id: "s1", seq: 2, type: "msg",
      payload: { text: "hi" }, trace_id: "t1", causation_id: "c1"
    )
    assert_equal "t1", event.trace_id
    assert_equal "c1", event.causation_id
    assert_equal({ text: "hi" }, event.payload)
  end

  def test_event_keyword_init
    now = Time.utc(2026, 1, 1)
    event = Ask::Session::Event.new(
      session_id: "s1", seq: 1, type: "x",
      payload: {}, trace_id: "t", causation_id: nil, created_at: now
    )
    assert_equal now, event.created_at
  end

  def test_event_equality
    now = Time.utc(2026, 1, 1)
    e1 = Ask::Session::Event.new(session_id: "s1", seq: 1, type: "x", payload: {}, trace_id: "t", causation_id: nil, created_at: now)
    e2 = Ask::Session::Event.new(session_id: "s1", seq: 1, type: "x", payload: {}, trace_id: "t", causation_id: nil, created_at: now)
    assert_equal e1, e2
  end
end
