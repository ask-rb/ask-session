# frozen_string_literal: true

require_relative "test_helper"

class HostCreateTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_create_returns_reduced_record
    record = @host.create(id: "s1")
    assert_equal "s1", record.id
    assert_equal :active, record.status
  end

  def test_create_emits_session_created_event
    record = @host.create(id: "s1", metadata: { key: "val" })
    events = @store.events("s1")
    assert_equal 1, events.size
    assert_equal "session.created", events.first.type
    assert_equal({ session_id: "s1", metadata: { key: "val" }, status: :active }, events.first.payload)
    assert_equal 1, events.first.seq
  end

  def test_create_with_deterministic_id
    record = @host.create(id: "custom_id")
    assert_equal "custom_id", record.id
  end

  def test_create_with_trace_id
    @host.create(id: "s1", trace_id: "t1")
    events = @store.events("s1")
    assert_equal "t1", events.first.trace_id
  end

  def test_create_duplicate_raises
    @host.create(id: "s1")
    assert_raises(Ask::Session::DuplicateSessionError) { @host.create(id: "s1") }
  end
end

class HostSessionTest < Minitest::Test
  include TestHelpers

  def setup
    @host = Ask::Session::Host.new(store: Ask::Session::Store.new)
  end

  def test_session_returns_reduced_record
    @host.create(id: "s1")
    record = @host.session("s1")
    assert_equal "s1", record.id
    assert_equal :active, record.status
  end

  def test_session_raises_for_missing
    assert_raises(Ask::Session::NotFoundError) { @host.session("missing") }
  end
end

class HostListTest < Minitest::Test
  def setup
    @host = Ask::Session::Host.new(store: Ask::Session::Store.new)
  end

  def test_list_returns_all_sessions
    @host.create(id: "s1")
    @host.create(id: "s2")
    list = @host.list
    assert_equal 2, list.size
  end
end

class HostSendMessageTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_send_message_returns_event
    @host.create(id: "s1")
    event = @host.send_message("s1", content: "hello")
    assert_kind_of Ask::Session::Event, event
    assert_equal "message.added", event.type
    assert_equal({ content: "hello" }, event.payload)
    assert_equal 2, event.seq
  end

  def test_send_message_with_trace_and_causation
    @host.create(id: "s1")
    created_event = @store.events("s1").first
    event = @host.send_message("s1", content: "hi", trace_id: "t2", causation_id: created_event.trace_id)
    assert_equal "t2", event.trace_id
    assert_equal created_event.trace_id, event.causation_id
  end

  def test_send_message_increments_seq
    @host.create(id: "s1")
    @host.send_message("s1", content: "a")
    e2 = @host.send_message("s1", content: "b")
    assert_equal 3, e2.seq
  end

  def test_send_message_raises_for_missing_session
    assert_raises(Ask::Session::NotFoundError) { @host.send_message("missing", content: "x") }
  end

  def test_send_message_raises_for_closed_session
    @host.create(id: "s1")
    @host.close("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.send_message("s1", content: "x") }
  end

  def test_send_message_raises_for_aborted_session
    @host.create(id: "s1")
    @host.abort("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.send_message("s1", content: "x") }
  end
end

class HostCloseTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_close_returns_reduced_record
    @host.create(id: "s1")
    record = @host.close("s1", reason: "done")
    assert_equal "s1", record.id
    assert_equal :closed, record.status
  end

  def test_close_emits_status_event
    @host.create(id: "s1")
    @host.close("s1", reason: "done")
    events = @store.events("s1")
    status_event = events.last
    assert_equal "session.ended", status_event.type
    assert_equal({ status: :closed, reason: "done" }, status_event.payload)
    assert_equal 2, status_event.seq
  end

  def test_close_raises_for_missing_session
    assert_raises(Ask::Session::NotFoundError) { @host.close("missing") }
  end

  def test_close_raises_for_already_closed
    @host.create(id: "s1")
    @host.close("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.close("s1") }
  end

  def test_close_raises_for_aborted_session
    @host.create(id: "s1")
    @host.abort("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.close("s1") }
  end
end

class HostAbortTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_abort_returns_reduced_record
    @host.create(id: "s1")
    record = @host.abort("s1", reason: "error")
    assert_equal "s1", record.id
    assert_equal :aborted, record.status
  end

  def test_abort_emits_status_event
    @host.create(id: "s1")
    @host.abort("s1", reason: "error")
    events = @store.events("s1")
    status_event = events.last
    assert_equal "session.aborted", status_event.type
    assert_equal({ status: :aborted, reason: "error" }, status_event.payload)
    assert_equal 2, status_event.seq
  end

  def test_abort_raises_for_already_aborted
    @host.create(id: "s1")
    @host.abort("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.abort("s1") }
  end

  def test_abort_raises_for_closed_session
    @host.create(id: "s1")
    @host.close("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.abort("s1") }
  end
end

class HostEventsTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_events_returns_all_by_default
    @host.create(id: "s1")
    @host.send_message("s1", content: "a")
    events = @host.events("s1")
    assert_equal 2, events.size
  end

  def test_events_after_seq_filters
    @host.create(id: "s1")
    @host.send_message("s1", content: "a")
    @host.send_message("s1", content: "b")
    events = @host.events("s1", after_seq: 1)
    assert_equal 2, events.size
    assert events.all? { |e| e.seq > 1 }
  end

  def test_events_raises_for_missing_session
    assert_raises(Ask::Session::NotFoundError) { @host.events("missing") }
  end
end

class HostReplayTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_subscribe_replays_existing_events
    @host.create(id: "s1")
    @host.send_message("s1", content: "a")
    @host.send_message("s1", content: "b")

    sub = @host.subscribe("s1")
    received = []
    3.times { received << sub.wait(timeout: 0.1) }
    sub.close

    types = received.map(&:type)
    assert_includes types, "session.created"
    assert_includes types, "message.added"
    assert_equal 3, received.size
  end

  def test_subscribe_with_after_seq_replays_subset
    @host.create(id: "s1")
    @host.send_message("s1", content: "a")
    @host.send_message("s1", content: "b")

    sub = @host.subscribe("s1", after_seq: 1)
    received = []
    2.times { received << sub.wait(timeout: 0.1) }
    sub.close

    assert received.all? { |e| e.seq > 1 }
    assert_equal 2, received.size
  end
end

class HostLiveDeliveryTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_live_events_delivered_after_subscribe
    @host.create(id: "s1")
    sub = @host.subscribe("s1")
    sub.wait(timeout: 0.1) # consume replay

    @host.send_message("s1", content: "live")
    event = sub.wait(timeout: 0.5)
    sub.close

    assert_equal "message.added", event.type
    assert_equal({ content: "live" }, event.payload)
  end

  def test_multiple_subscribers_receive_events
    @host.create(id: "s1")
    sub1 = @host.subscribe("s1")
    sub2 = @host.subscribe("s1")

    @host.send_message("s1", content: "x")
    e1 = sub1.wait(timeout: 0.5)
    e2 = sub2.wait(timeout: 0.5)

    sub1.close
    sub2.close

    assert_equal e1.seq, e2.seq
    assert_equal e1.type, e2.type
  end

  def test_live_event_not_delivered_to_different_session
    @host.create(id: "s1")
    @host.create(id: "s2")
    sub = @host.subscribe("s1")
    sub.wait(timeout: 0.1) # consume replay

    @host.send_message("s2", content: "other")
    event = sub.wait(timeout: 0.1)
    sub.close

    assert_nil event
  end
end

class HostSubscriptionCloseTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_next_returns_nil_after_close
    @host.create(id: "s1")
    sub = @host.subscribe("s1")
    sub.close
    assert_nil sub.wait(timeout: 0.1)
  end

  def test_closed_returns_true_after_close
    @host.create(id: "s1")
    sub = @host.subscribe("s1")
    refute sub.closed?
    sub.close
    assert sub.closed?
  end

  def test_each_yields_until_closed
    @host.create(id: "s1")
    @host.send_message("s1", content: "a")

    sub = @host.subscribe("s1")
    sub.wait(timeout: 0.1) # consume replay: session.created
    sub.wait(timeout: 0.1) # consume replay: message.added

    received = []
    thread = Thread.new do
      sub.each { |e| received << e; break if received.size == 1 }
    end

    @host.send_message("s1", content: "b")
    thread.join(1)
    sub.close

    assert_equal 1, received.size
    assert received.all? { |e| e.type == "message.added" }
  end

  def test_each_stops_after_close
    @host.create(id: "s1")
    sub = @host.subscribe("s1")
    sub.close

    received = []
    sub.each { |e| received << e }
    assert_empty received
  end
end

class HostSubscriptionTimeoutTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_next_returns_nil_on_timeout
    @host.create(id: "s1")
    sub = Ask::Session::Subscription.new(id: 1, session_id: "s1")
    result = sub.wait(timeout: 0.05)
    sub.close
    assert_nil result
  end
end

class HostSubscriptionBoundaryOrderTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_replay_then_live_no_gap_no_overlap
    @host.create(id: "s1")
    @host.send_message("s1", content: "before")

    sub = @host.subscribe("s1")
    @host.send_message("s1", content: "after")

    received = []
    3.times { received << sub.wait(timeout: 0.2) }
    sub.close

    seqs = received.map(&:seq)
    assert_equal [1, 2, 3], seqs

    types = received.map(&:type)
    assert_equal ["session.created", "message.added", "message.added"], types
  end

  def test_subscribe_after_seq_then_live
    @host.create(id: "s1")
    @host.send_message("s1", content: "a")
    @host.send_message("s1", content: "b")

    sub = @host.subscribe("s1", after_seq: 2)
    @host.send_message("s1", content: "c")

    received = []
    2.times { received << sub.wait(timeout: 0.2) }
    sub.close

    seqs = received.map(&:seq)
    assert_equal [3, 4], seqs
  end
end
