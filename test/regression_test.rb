# frozen_string_literal: true

require_relative "test_helper"

class RegressionImmutabilityTest < Minitest::Test
  include TestHelpers

  # --- Record ---

  def test_record_frozen_after_create
    record = Ask::Session::Record.create(id: "s1")
    assert record.frozen?, "Record.create result must be frozen"
  end

  def test_record_frozen_after_keyword_init
    record = build_record
    assert record.frozen?, "Record.new result must be frozen"
  end

  def test_with_updates_returns_frozen_record
    record = build_record
    updated = record.with_updates(status: :completed, version: 1)
    assert updated.frozen?, "with_updates result must be frozen"
  end

  def test_record_metadata_is_deep_copied_and_frozen
    input = { nested: { deep: "value" } }
    record = Ask::Session::Record.create(id: "s1", metadata: input)

    # Mutating the original must not affect the record
    input[:nested][:deep] = "CHANGED"
    assert_equal "value", record.metadata[:nested][:deep],
      "Record must defensively copy metadata"
  end

  def test_record_metadata_frozen
    record = build_record
    assert record.metadata.frozen?, "Record metadata must be frozen"
  end

  # --- Event ---

  def test_event_frozen_after_create
    event = Ask::Session::Event.create(session_id: "s1", seq: 1, type: "x")
    assert event.frozen?, "Event.create result must be frozen"
  end

  def test_event_frozen_after_keyword_init
    event = build_event
    assert event.frozen?, "Event.new result must be frozen"
  end

  def test_event_payload_is_deep_copied_and_frozen
    input = { nested: { deep: "value" } }
    event = Ask::Session::Event.create(session_id: "s1", seq: 1, type: "x", payload: input)

    input[:nested][:deep] = "CHANGED"
    assert_equal "value", event.payload[:nested][:deep],
      "Event must defensively copy payload"
  end

  def test_event_payload_frozen
    event = build_event
    assert event.payload.frozen?, "Event payload must be frozen"
  end
end

class RegressionSequenceTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
  end

  def test_append_event_rejects_non_sequential_seq
    @store.create(id: "s1")
    event = build_event(session_id: "s1", seq: 5)
    assert_raises(Ask::Session::ConcurrencyError) do
      @store.append_event(event, expected_sequence: 0)
    end
  end

  def test_append_event_rejects_stale_seq
    @store.create(id: "s1")
    e1 = build_event(session_id: "s1", seq: 1)
    @store.append_event(e1, expected_sequence: 0)

    stale = build_event(session_id: "s1", seq: 1)
    assert_raises(Ask::Session::ConcurrencyError) do
      @store.append_event(stale, expected_sequence: 1)
    end
  end

  def test_append_event_rejects_skipped_seq
    @store.create(id: "s1")
    e1 = build_event(session_id: "s1", seq: 1)
    @store.append_event(e1, expected_sequence: 0)

    skipped = build_event(session_id: "s1", seq: 3)
    assert_raises(Ask::Session::ConcurrencyError) do
      @store.append_event(skipped, expected_sequence: 1)
    end
  end

  def test_events_remain_monotonic_after_rejection
    @store.create(id: "s1")
    e1 = build_event(session_id: "s1", seq: 1)
    @store.append_event(e1, expected_sequence: 0)

    skipped = build_event(session_id: "s1", seq: 5)
    assert_raises(Ask::Session::ConcurrencyError) do
      @store.append_event(skipped, expected_sequence: 0)
    end

    # The store must still accept the correct next event
    e2 = build_event(session_id: "s1", seq: 2)
    @store.append_event(e2, expected_sequence: 1)
    assert_equal 2, @store.current_sequence("s1")
  end
end

class RegressionDuplicateTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
  end

  def test_create_rejects_duplicate_id
    @store.create(id: "s1")
    assert_raises(Ask::Session::DuplicateSessionError) do
      @store.create(id: "s1")
    end
  end

  def test_create_duplicate_does_not_overwrite_original
    @store.create(id: "s1", status: :active)
    begin
      @store.create(id: "s1", status: :completed)
    rescue Ask::Session::DuplicateSessionError
      # expected
    end
    loaded = @store.load("s1")
    assert_equal :active, loaded.status,
      "Original record must not be overwritten by duplicate create"
  end
end

class RegressionNotFoundErrorTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
  end

  def test_load_missing_raises_not_found_error
    assert_raises(Ask::Session::NotFoundError) do
      @store.load!("nonexistent")
    end
  end

  def test_not_found_error_is_subclass_of_error
    assert Ask::Session::NotFoundError.ancestors.include?(Ask::Session::Error),
      "NotFoundError must be a subclass of Ask::Session::Error"
  end

  def test_append_event_on_missing_session_raises_not_found
    event = build_event(session_id: "missing", seq: 1)
    assert_raises(Ask::Session::NotFoundError) do
      @store.append_event(event, expected_sequence: 0)
    end
  end

  def test_events_after_on_missing_session_raises_not_found
    assert_raises(Ask::Session::NotFoundError) do
      @store.events_after("missing", after_seq: 0)
    end
  end

  def test_current_sequence_on_missing_session_raises_not_found
    assert_raises(Ask::Session::NotFoundError) do
      @store.current_sequence("missing")
    end
  end
end

class RegressionStateFreezeTest < Minitest::Test
  include TestHelpers

  def test_reduce_returns_frozen_record
    e1 = build_event(session_id: "s1", seq: 1, type: "session.created",
      payload: { status: :active, metadata: { key: "val" } })
    record = Ask::Session::State.reduce("s1", [e1])
    assert record.frozen?, "State.reduce must return a frozen record"
  end

  def test_reduce_default_returns_frozen_record
    record = Ask::Session::State.reduce("s1", [])
    assert record.frozen?, "State.reduce with empty events must return a frozen record"
  end
end
