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
    @host.create(id: "s1", metadata: { key: "val" })
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

class HostDefaultStoreTest < Minitest::Test
  def test_initialize_without_store_creates_working_host
    host = Ask::Session::Host.new
    record = host.create(id: "s1")
    assert_equal "s1", record.id
    assert_equal :active, record.status
  end
end

class HostListReflectsStateTest < Minitest::Test
  def setup
    @host = Ask::Session::Host.new(store: Ask::Session::Store.new)
  end

  def test_list_reflects_closed_status
    @host.create(id: "s1")
    @host.close("s1", reason: "done")
    list = @host.list
    s1 = list.find { |r| r.id == "s1" }
    assert_equal :closed, s1.status
  end

  def test_list_reflects_aborted_status
    @host.create(id: "s1")
    @host.abort("s1", reason: "error")
    list = @host.list
    s1 = list.find { |r| r.id == "s1" }
    assert_equal :aborted, s1.status
  end
end

class HostCreateMutexTest < Minitest::Test
  def test_create_wraps_operations_under_mutex
    host = Ask::Session::Host.new(store: Ask::Session::Store.new)
    record = host.create(id: "s1")
    sub = host.subscribe("s1")
    event = sub.wait(timeout: 0.5)
    sub.close
    assert_equal "session.created", event.type
    assert_equal "s1", record.id
  end
end

class SubscriptionNextTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_next_returns_event
    @host.create(id: "s1")
    sub = @host.subscribe("s1")
    event = sub.next(timeout: 0.5)
    sub.close
    assert_kind_of Ask::Session::Event, event
  end

  def test_next_returns_nil_on_timeout
    sub = Ask::Session::Subscription.new(id: 1, session_id: "s1")
    result = sub.next(timeout: 0.05)
    sub.close
    assert_nil result
  end

  def test_next_returns_nil_when_closed
    @host.create(id: "s1")
    sub = @host.subscribe("s1")
    sub.close
    assert_nil sub.next(timeout: 0.1)
  end

  def test_wait_is_alias_for_next
    sub = Ask::Session::Subscription.new(id: 1, session_id: "s1")
    assert_equal sub.method(:next), sub.method(:wait)
    sub.close
  end
end

class SubscriptionCloseWakesBlockedTest < Minitest::Test
  def test_close_wakes_blocked_next_with_nil
    sub = Ask::Session::Subscription.new(id: 1, session_id: "s1")
    result = nil
    thread = Thread.new { result = sub.next(timeout: 1.0) }
    sleep 0.05
    sub.close
    thread.join(1)
    assert_nil result
  end
end

class HostPublishPrunesClosedTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_publish_removes_closed_subscriptions
    @host.create(id: "s1")
    sub1 = @host.subscribe("s1")
    sub2 = @host.subscribe("s1")
    sub1.wait(timeout: 0.1) # consume replay
    sub2.wait(timeout: 0.1) # consume replay
    sub1.close

    @host.send_message("s1", content: "x")
    event = sub2.wait(timeout: 0.5)
    sub2.close

    assert_equal "message.added", event.type
    assert_equal({ content: "x" }, event.payload)
  end
end

class HostAppendTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
  end

  def test_append_returns_event
    @host.create(id: "s1")
    event = @host.append("s1", type: "tool.started", payload: { tool: "search" })
    assert_kind_of Ask::Session::Event, event
    assert_equal "tool.started", event.type
    assert_equal({ tool: "search" }, event.payload)
  end

  def test_append_assigns_next_seq
    @host.create(id: "s1")
    e1 = @host.append("s1", type: "tool.started")
    e2 = @host.append("s1", type: "tool.completed")
    assert_equal 2, e1.seq
    assert_equal 3, e2.seq
  end

  def test_append_preserves_trace_id
    @host.create(id: "s1")
    event = @host.append("s1", type: "custom.event", trace_id: "trace_abc")
    assert_equal "trace_abc", event.trace_id
  end

  def test_append_preserves_causation_id
    @host.create(id: "s1")
    created_event = @store.events("s1").first
    event = @host.append("s1", type: "custom.event", causation_id: created_event.trace_id)
    assert_equal created_event.trace_id, event.causation_id
  end

  def test_append_default_empty_payload
    @host.create(id: "s1")
    event = @host.append("s1", type: "custom.event")
    assert_equal({}, event.payload)
  end

  def test_append_raises_for_missing_session
    assert_raises(Ask::Session::NotFoundError) { @host.append("missing", type: "x") }
  end

  def test_append_raises_for_closed_session
    @host.create(id: "s1")
    @host.close("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.append("s1", type: "x") }
  end

  def test_append_raises_for_aborted_session
    @host.create(id: "s1")
    @host.abort("s1")
    assert_raises(Ask::Session::InvalidTransitionError) { @host.append("s1", type: "x") }
  end

  def test_append_advances_state_version
    @host.create(id: "s1")
    @host.append("s1", type: "custom.a", payload: { x: 1 })
    @host.append("s1", type: "custom.b", payload: { x: 2 })
    record = @host.session("s1")
    assert_equal 3, record.version
  end

  def test_append_advances_updated_at
    @host.create(id: "s1")
    record_after_create = @host.session("s1")
    t_create = record_after_create.updated_at

    @host.append("s1", type: "custom.a")
    record_after_first = @host.session("s1")
    assert record_after_first.updated_at >= t_create

    @host.append("s1", type: "custom.b")
    record_after_second = @host.session("s1")
    assert record_after_second.updated_at >= record_after_first.updated_at
    assert_equal 3, record_after_second.version
  end

  def test_append_preserves_existing_status
    @host.create(id: "s1")
    @host.append("s1", type: "custom.event")
    record = @host.session("s1")
    assert_equal :active, record.status
  end

  def test_append_publishes_to_subscribers
    @host.create(id: "s1")
    sub = @host.subscribe("s1")
    sub.wait(timeout: 0.1) # consume replay

    @host.append("s1", type: "custom.event", payload: { data: 42 })
    event = sub.wait(timeout: 0.5)
    sub.close

    assert_equal "custom.event", event.type
    assert_equal({ data: 42 }, event.payload)
  end

  def test_append_replay_includes_all_events
    @host.create(id: "s1")
    @host.append("s1", type: "custom.a")
    @host.append("s1", type: "custom.b")

    sub = @host.subscribe("s1")
    received = []
    3.times { received << sub.wait(timeout: 0.1) }
    sub.close

    types = received.map(&:type)
    assert_equal ["session.created", "custom.a", "custom.b"], types
  end

  def test_append_unknown_event_advances_version
    @host.create(id: "s1")
    @host.append("s1", type: "vendor.webhook.received", payload: { raw: "data" })
    record = @host.session("s1")
    assert_equal 2, record.version
    assert_equal :active, record.status
  end

  def test_append_unknown_event_advances_updated_at
    @host.create(id: "s1")
    @host.append("s1", type: "vendor.webhook.received")
    record = @host.session("s1")
    assert_equal 2, record.version
    refute_nil record.updated_at
  end

  def test_append_generic_event_type_round_trip
    @host.create(id: "s1")
    @host.append("s1", type: "custom.phase.started", payload: { phase: "discovery" })
    @host.close("s1", reason: "complete")

    events = @store.events("s1")
    types = events.map(&:type)
    assert_equal ["session.created", "custom.phase.started", "session.ended"], types

    record = @host.session("s1")
    assert_equal :closed, record.status
    assert_equal 3, record.version
  end
end
