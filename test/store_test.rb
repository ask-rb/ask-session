# frozen_string_literal: true

require_relative "test_helper"

class StoreTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
  end

  def test_create_returns_record
    record = @store.create(id: "s1")
    assert_equal "s1", record.id
    assert_equal :active, record.status
  end

  def test_create_with_defaults
    record = @store.create
    assert record.id.start_with?("sess_")
  end

  def test_load_returns_record
    @store.create(id: "s1")
    loaded = @store.load("s1")
    assert_equal "s1", loaded.id
  end

  def test_load_returns_nil_for_missing
    assert_nil @store.load("nonexistent")
  end

  def test_list_returns_all_sessions
    @store.create(id: "s1")
    @store.create(id: "s2")
    list = @store.list
    assert_equal 2, list.size
    assert list.any? { |r| r.id == "s1" }
    assert list.any? { |r| r.id == "s2" }
  end

  def test_append_event_with_correct_sequence
    @store.create(id: "s1")
    event = build_event(session_id: "s1", seq: 1)
    result = @store.append_event(event, expected_sequence: 0)
    assert_equal event, result
  end

  def test_append_event_raises_on_wrong_sequence
    @store.create(id: "s1")
    event = build_event(session_id: "s1", seq: 1)
    @store.append_event(event, expected_sequence: 0)

    event2 = build_event(session_id: "s1", seq: 2)
    assert_raises(Ask::Session::ConcurrencyError) do
      @store.append_event(event2, expected_sequence: 0)
    end
  end

  def test_append_event_raises_on_missing_session
    event = build_event(session_id: "missing", seq: 1)
    assert_raises(Ask::Session::NotFoundError) do
      @store.append_event(event, expected_sequence: 0)
    end
  end

  def test_events_after_returns_correct_subset
    @store.create(id: "s1")
    e1 = build_event(session_id: "s1", seq: 1)
    e2 = build_event(session_id: "s1", seq: 2)
    e3 = build_event(session_id: "s1", seq: 3)
    @store.append_event(e1, expected_sequence: 0)
    @store.append_event(e2, expected_sequence: 1)
    @store.append_event(e3, expected_sequence: 2)

    events = @store.events_after("s1", after_seq: 1)
    assert_equal 2, events.size
    assert events.all? { |e| e.seq > 1 }
  end

  def test_events_after_raises_on_missing_session
    assert_raises(Ask::Session::NotFoundError) do
      @store.events_after("missing", after_seq: 0)
    end
  end

  def test_current_sequence_returns_count
    @store.create(id: "s1")
    assert_equal 0, @store.current_sequence("s1")

    @store.append_event(build_event(session_id: "s1", seq: 1), expected_sequence: 0)
    assert_equal 1, @store.current_sequence("s1")
  end

  def test_current_sequence_raises_on_missing
    assert_raises(Ask::Session::NotFoundError) do
      @store.current_sequence("missing")
    end
  end
end
