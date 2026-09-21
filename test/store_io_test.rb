# frozen_string_literal: true

require_relative "test_helper"

class StoreEventsTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
  end

  def test_events_returns_frozen_array
    @store.create(id: "s1")
    @store.append_event(build_event(session_id: "s1", seq: 1), expected_sequence: 0)

    events = @store.events("s1")
    assert events.frozen?, "events must return a frozen array"
    assert_equal 1, events.size
  end

  def test_events_returns_empty_frozen_array_for_new_session
    @store.create(id: "s1")
    events = @store.events("s1")
    assert events.frozen?
    assert_equal 0, events.size
  end

  def test_events_raises_for_missing_session
    assert_raises(Ask::Session::NotFoundError) do
      @store.events("missing")
    end
  end
end

class StoreExportTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
  end

  def test_export_returns_hash_with_sessions_and_events
    @store.create(id: "s1")
    @store.append_event(build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active }), expected_sequence: 0)
    @store.append_event(build_event(session_id: "s1", seq: 2, type: "message.added",
      payload: { role: :user }), expected_sequence: 1)

    data = @store.export
    assert_kind_of Hash, data
    assert data.key?(:sessions)
    assert data.key?(:events)
  end

  def test_export_sessions_contain_record_hashes
    @store.create(id: "s1", status: :active, metadata: { k: "v" })
    data = @store.export

    assert_equal 1, data[:sessions].size
    session_data = data[:sessions].first
    assert_equal "s1", session_data[:id]
    assert_equal :active, session_data[:status]
  end

  def test_export_events_contain_event_hashes
    @store.create(id: "s1")
    @store.append_event(build_event(session_id: "s1", seq: 1), expected_sequence: 0)

    data = @store.export
    assert_equal 1, data[:events].size
    event_data = data[:events].first
    assert_equal "s1", event_data[:session_id]
    assert_equal 1, event_data[:seq]
  end

  def test_export_json_round_trip
    @store.create(id: "s1", status: :active, metadata: { nested: { a: 1 } })
    @store.append_event(build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active, nested: { b: 2 } }), expected_sequence: 0)

    data = @store.export
    json = JSON.generate(data)
    parsed = JSON.parse(json, symbolize_names: true)
    new_store = Ask::Session::Store.new
    new_store.import(parsed)

    assert_equal 1, new_store.list.size
    loaded = new_store.load("s1")
    assert_equal "s1", loaded.id
    assert_equal :active, loaded.status
    assert_equal({ nested: { a: 1 } }, loaded.metadata)
    assert_equal 1, new_store.current_sequence("s1")
  end
end

class StoreImportTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
  end

  def test_import_restores_sessions
    data = {
      sessions: [
        { id: "s1", status: :active, metadata: {},
          created_at: Time.utc(2026, 1, 1).iso8601,
          updated_at: Time.utc(2026, 1, 1).iso8601, version: 0 }
      ],
      events: []
    }
    @store.import(data)

    loaded = @store.load("s1")
    assert_equal "s1", loaded.id
    assert_equal :active, loaded.status
  end

  def test_import_restores_events
    data = {
      sessions: [
        { id: "s1", status: :active, metadata: {},
          created_at: Time.utc(2026, 1, 1).iso8601,
          updated_at: Time.utc(2026, 1, 1).iso8601, version: 0 }
      ],
      events: [
        { session_id: "s1", seq: 1, type: "session.created",
          payload: { status: :active }, trace_id: "t1",
          causation_id: nil, created_at: Time.utc(2026, 1, 1).iso8601 }
      ]
    }
    @store.import(data)

    events = @store.events("s1")
    assert_equal 1, events.size
    assert_equal "session.created", events.first.type
    assert_equal 1, @store.current_sequence("s1")
  end

  def test_import_rejects_duplicate_session_id
    @store.create(id: "s1")
    data = {
      sessions: [
        { id: "s1", status: :active, metadata: {},
          created_at: Time.utc(2026, 1, 1).iso8601,
          updated_at: Time.utc(2026, 1, 1).iso8601, version: 0 }
      ],
      events: []
    }

    assert_raises(Ask::Session::DuplicateSessionError) do
      @store.import(data)
    end
  end

  def test_import_rejects_bad_sequence_data
    data = {
      sessions: [
        { id: "s1", status: :active, metadata: {},
          created_at: Time.utc(2026, 1, 1).iso8601,
          updated_at: Time.utc(2026, 1, 1).iso8601, version: 0 }
      ],
      events: [
        { session_id: "s1", seq: 1, type: "session.created",
          payload: {}, trace_id: "t1", causation_id: nil,
          created_at: Time.utc(2026, 1, 1).iso8601 },
        { session_id: "s1", seq: 3, type: "message.added",
          payload: {}, trace_id: "t2", causation_id: nil,
          created_at: Time.utc(2026, 1, 2).iso8601 }
      ]
    }

    assert_raises(Ask::Session::ConcurrencyError) do
      @store.import(data)
    end
  end

  def test_import_rejects_event_for_missing_session
    data = {
      sessions: [],
      events: [
        { session_id: "missing", seq: 1, type: "session.created",
          payload: {}, trace_id: "t1", causation_id: nil,
          created_at: Time.utc(2026, 1, 1).iso8601 }
      ]
    }

    assert_raises(Ask::Session::NotFoundError) do
      @store.import(data)
    end
  end

  def test_export_import_round_trip_preserves_state
    @store.create(id: "s1", status: :active, metadata: { key: "val" })
    @store.append_event(build_event(session_id: "s1", seq: 1,
      type: "session.created", payload: { status: :active },
      created_at: Time.utc(2026, 1, 1)), expected_sequence: 0)
    @store.append_event(build_event(session_id: "s1", seq: 2,
      type: "message.added", payload: { content: "hello" },
      created_at: Time.utc(2026, 1, 2)), expected_sequence: 1)

    data = @store.export
    new_store = Ask::Session::Store.new
    new_store.import(data)

    loaded = new_store.load("s1")
    assert_equal :active, loaded.status
    assert_equal({ key: "val" }, loaded.metadata)

    events = new_store.events("s1")
    assert_equal 2, events.size
    assert_equal "session.created", events[0].type
    assert_equal "message.added", events[1].type
    assert_equal 2, new_store.current_sequence("s1")
  end

  def test_export_import_round_trip_multiple_sessions
    @store.create(id: "s1", status: :active)
    @store.append_event(build_event(session_id: "s1", seq: 1,
      type: "session.created", payload: { status: :active }),
      expected_sequence: 0)

    @store.create(id: "s2", status: :completed)
    @store.append_event(build_event(session_id: "s2", seq: 1,
      type: "session.created", payload: { status: :completed }),
      expected_sequence: 0)

    data = @store.export
    new_store = Ask::Session::Store.new
    new_store.import(data)

    assert_equal 2, new_store.list.size
    assert_equal :active, new_store.load("s1").status
    assert_equal :completed, new_store.load("s2").status
    assert_equal 1, new_store.current_sequence("s1")
    assert_equal 1, new_store.current_sequence("s2")
  end
end
