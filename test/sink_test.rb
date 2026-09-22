# frozen_string_literal: true

require_relative "test_helper"

# Duck-typed stand-ins for Ask::Runtime::Events::* and the objects they
# carry. They mirror the public reader surface of the real runtime types
# (ToolStarted, ToolCompleted, ToolFailed, ToolCancelled, ToolTimedOut,
# ToolCall, ToolResult, ExecutionContext) so the Sink contract can be
# verified without a runtime dependency.
module SinkStubs
  class ToolCall
    attr_reader :id, :tool_name, :input, :session_id, :turn, :state

    def initialize(id:, tool_name:, input: {}, session_id: nil, turn: nil, state: :running)
      @id = id
      @tool_name = tool_name
      @input = input
      @session_id = session_id
      @turn = turn
      @state = state
    end
  end

  class ExecutionContext
    attr_reader :session_id, :turn

    def initialize(session_id: nil, turn: nil)
      @session_id = session_id
      @turn = turn
    end
  end

  class ToolResult
    attr_reader :output, :error_message, :outcome

    def initialize(output: nil, error_message: nil, outcome: :success)
      @output = output
      @error_message = error_message
      @outcome = outcome
    end
  end

  class ToolStarted
    attr_reader :tool_call, :tool_name, :tool_call_id, :execution_context

    def initialize(tool_call:, execution_context:)
      @tool_call = tool_call
      @tool_name = tool_call.tool_name
      @tool_call_id = tool_call.id
      @execution_context = execution_context
    end
  end

  class ToolCompleted
    attr_reader :tool_call, :tool_name, :tool_call_id, :execution_context,
                :duration, :tool_result

    def initialize(tool_call:, execution_context:, duration:, tool_result:)
      @tool_call = tool_call
      @tool_name = tool_call.tool_name
      @tool_call_id = tool_call.id
      @execution_context = execution_context
      @duration = duration
      @tool_result = tool_result
    end
  end

  class ToolFailed
    attr_reader :tool_call, :tool_name, :tool_call_id, :execution_context,
                :duration, :tool_result, :error

    def initialize(tool_call:, execution_context:, duration:, tool_result:, error: nil)
      @tool_call = tool_call
      @tool_name = tool_call.tool_name
      @tool_call_id = tool_call.id
      @execution_context = execution_context
      @duration = duration
      @tool_result = tool_result
      @error = error
    end
  end

  class ToolCancelled
    attr_reader :tool_call, :tool_name, :tool_call_id, :execution_context,
                :duration, :tool_result, :reason

    def initialize(tool_call:, execution_context:, duration:, tool_result:, reason: nil)
      @tool_call = tool_call
      @tool_name = tool_call.tool_name
      @tool_call_id = tool_call.id
      @execution_context = execution_context
      @duration = duration
      @tool_result = tool_result
      @reason = reason
    end
  end

  class ToolTimedOut
    attr_reader :tool_call, :tool_name, :tool_call_id, :execution_context,
                :duration, :tool_result

    def initialize(tool_call:, execution_context:, duration:, tool_result:)
      @tool_call = tool_call
      @tool_name = tool_call.tool_name
      @tool_call_id = tool_call.id
      @execution_context = execution_context
      @duration = duration
      @tool_result = tool_result
    end
  end
end

class SinkEmitMappingTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
    @host.create(id: "s1")
    @sink = Ask::Session::Sink.new(host: @host, session_id: "s1")
  end

  def started_event(session_id: "s1", turn: 3)
    call = SinkStubs::ToolCall.new(
      id: "tc_1", tool_name: "bash", input: { "cmd" => "ls" },
      session_id: session_id, turn: turn, state: :running
    )
    ctx = SinkStubs::ExecutionContext.new(session_id: session_id, turn: turn)
    SinkStubs::ToolStarted.new(tool_call: call, execution_context: ctx)
  end

  def completed_event(session_id: "s1", turn: 3, duration: 1.25, output: ["a.txt"])
    call = SinkStubs::ToolCall.new(
      id: "tc_1", tool_name: "bash", input: { "cmd" => "ls" },
      session_id: session_id, turn: turn, state: :completed
    )
    ctx = SinkStubs::ExecutionContext.new(session_id: session_id, turn: turn)
    result = SinkStubs::ToolResult.new(output: output, outcome: :success)
    SinkStubs::ToolCompleted.new(
      tool_call: call, execution_context: ctx, duration: duration, tool_result: result
    )
  end

  def test_tool_started_maps_to_tool_started_event
    @sink.emit(:tool_started, event: started_event)

    event = @store.events("s1").last
    assert_equal "tool.started", event.type
    assert_equal 2, event.seq
    assert_equal "bash", event.payload[:tool_name]
    assert_equal "tc_1", event.payload[:tool_call_id]
    assert_equal({ "cmd" => "ls" }, event.payload[:input])
    assert_equal 3, event.payload[:turn]
  end

  def test_tool_completed_maps_to_tool_completed_event
    @sink.emit(:tool_completed, event: completed_event)

    event = @store.events("s1").last
    assert_equal "tool.completed", event.type
    assert_equal "bash", event.payload[:tool_name]
    assert_equal "tc_1", event.payload[:tool_call_id]
    assert_equal :completed, event.payload[:outcome]
    assert_equal 1.25, event.payload[:duration]
    assert_equal ["a.txt"], event.payload[:output]
    assert_equal 3, event.payload[:turn]
  end

  def test_tool_failed_maps_to_tool_failed_event
    call = SinkStubs::ToolCall.new(id: "tc_2", tool_name: "read", session_id: "s1", state: :failed)
    ctx = SinkStubs::ExecutionContext.new(session_id: "s1")
    result = SinkStubs::ToolResult.new(error_message: "file not found", outcome: :failure)
    event = SinkStubs::ToolFailed.new(
      tool_call: call, execution_context: ctx, duration: 0.2,
      tool_result: result, error: "file not found"
    )

    @sink.emit(:tool_failed, event: event)

    appended = @store.events("s1").last
    assert_equal "tool.failed", appended.type
    assert_equal :failed, appended.payload[:outcome]
    assert_equal "file not found", appended.payload[:error]
    assert_equal 0.2, appended.payload[:duration]
    refute appended.payload.key?(:output)
  end

  def test_tool_cancelled_maps_to_tool_cancelled_event
    call = SinkStubs::ToolCall.new(id: "tc_3", tool_name: "bash", session_id: "s1", state: :cancelled)
    ctx = SinkStubs::ExecutionContext.new(session_id: "s1")
    result = SinkStubs::ToolResult.new(error_message: "user aborted", outcome: :cancelled)
    event = SinkStubs::ToolCancelled.new(
      tool_call: call, execution_context: ctx, duration: 0.5,
      tool_result: result, reason: "user aborted"
    )

    @sink.emit(:tool_cancelled, event: event)

    appended = @store.events("s1").last
    assert_equal "tool.cancelled", appended.type
    assert_equal :cancelled, appended.payload[:outcome]
    assert_equal "user aborted", appended.payload[:error]
  end

  def test_tool_timed_out_maps_to_tool_timed_out_event
    call = SinkStubs::ToolCall.new(id: "tc_4", tool_name: "bash", session_id: "s1", state: :timed_out)
    ctx = SinkStubs::ExecutionContext.new(session_id: "s1")
    result = SinkStubs::ToolResult.new(error_message: "Execution timed out", outcome: :timeout)
    event = SinkStubs::ToolTimedOut.new(
      tool_call: call, execution_context: ctx, duration: 30.0, tool_result: result
    )

    @sink.emit(:tool_timed_out, event: event)

    appended = @store.events("s1").last
    assert_equal "tool.timed_out", appended.type
    assert_equal :timed_out, appended.payload[:outcome]
    assert_equal 30.0, appended.payload[:duration]
    assert_equal "Execution timed out", appended.payload[:error]
  end

  def test_string_event_type_is_accepted
    @sink.emit("tool_started", event: started_event)
    assert_equal "tool.started", @store.events("s1").last.type
  end

  def test_unknown_event_type_is_ignored
    result = @sink.emit(:custom_vendor_event, event: started_event)
    assert_same @sink, result
    assert_equal 1, @store.events("s1").size
  end

  def test_mapped_type_without_event_raises
    assert_raises(ArgumentError) { @sink.emit(:tool_started) }
  end

  def test_emit_returns_self
    assert_same @sink, @sink.emit(:tool_started, event: started_event)
  end
end

class SinkCorrelationTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
    @host.create(id: "s1")
    @sink = Ask::Session::Sink.new(host: @host, session_id: "s1", trace_id: "trace_9")
  end

  def started_event(session_id:)
    call = SinkStubs::ToolCall.new(id: "tc_1", tool_name: "bash", session_id: session_id)
    ctx = SinkStubs::ExecutionContext.new(session_id: session_id)
    SinkStubs::ToolStarted.new(tool_call: call, execution_context: ctx)
  end

  def test_matching_session_id_from_tool_call_is_accepted
    @sink.emit(:tool_started, event: started_event(session_id: "s1"))
    assert_equal "tool.started", @store.events("s1").last.type
  end

  def test_nil_session_id_is_accepted_as_uncorrelated
    @sink.emit(:tool_started, event: started_event(session_id: nil))
    assert_equal "tool.started", @store.events("s1").last.type
  end

  def test_mismatched_session_id_raises
    error = assert_raises(Ask::Session::SessionMismatchError) do
      @sink.emit(:tool_started, event: started_event(session_id: "other"))
    end
    assert_match(/s1/, error.message)
    assert_match(/other/, error.message)
    assert_equal 1, @store.events("s1").size
  end

  def test_constructor_trace_id_is_preserved
    @sink.emit(:tool_started, event: started_event(session_id: "s1"))
    assert_equal "trace_9", @store.events("s1").last.trace_id
  end

  def test_constructor_causation_id_is_preserved
    created = @store.events("s1").first
    sink = Ask::Session::Sink.new(host: @host, session_id: "s1", causation_id: created.trace_id)
    sink.emit(:tool_started, event: started_event(session_id: "s1"))
    assert_equal created.trace_id, @store.events("s1").last.causation_id
  end
end

class SinkLifecycleTest < Minitest::Test
  def setup
    @store = Ask::Session::Store.new
    @host = Ask::Session::Host.new(store: @store)
    @host.create(id: "s1")
    @sink = Ask::Session::Sink.new(host: @host, session_id: "s1")
  end

  def completed_event
    call = SinkStubs::ToolCall.new(id: "tc_1", tool_name: "bash", session_id: "s1", state: :completed)
    ctx = SinkStubs::ExecutionContext.new(session_id: "s1")
    result = SinkStubs::ToolResult.new(output: "ok", outcome: :success)
    SinkStubs::ToolCompleted.new(tool_call: call, execution_context: ctx, duration: 0.1, tool_result: result)
  end

  def test_sink_events_are_published_to_subscribers
    sub = @host.subscribe("s1")
    sub.wait(timeout: 0.1) # consume replay

    @sink.emit(:tool_completed, event: completed_event)
    event = sub.wait(timeout: 0.5)
    sub.close

    assert_equal "tool.completed", event.type
  end

  def test_sink_events_advance_reduced_state_version
    @sink.emit(:tool_completed, event: completed_event)
    record = @host.session("s1")
    assert_equal 2, record.version
    assert_equal :active, record.status
  end

  def test_sink_on_closed_session_drops_event_without_raising
    @host.close("s1", reason: "done")
    result = @sink.emit(:tool_completed, event: completed_event)
    assert_same @sink, result
    assert_equal 2, @store.events("s1").size
  end

  def test_sink_on_aborted_session_drops_event_without_raising
    @host.abort("s1", reason: "error")
    result = @sink.emit(:tool_completed, event: completed_event)
    assert_same @sink, result
    assert_equal 2, @store.events("s1").size
  end

  def test_sink_on_missing_session_raises_not_found
    sink = Ask::Session::Sink.new(host: @host, session_id: "missing")
    call = SinkStubs::ToolCall.new(id: "tc_9", tool_name: "bash", session_id: nil)
    ctx = SinkStubs::ExecutionContext.new(session_id: nil)
    result = SinkStubs::ToolResult.new(output: "ok", outcome: :success)
    event = SinkStubs::ToolCompleted.new(
      tool_call: call, execution_context: ctx, duration: 0.1, tool_result: result
    )

    assert_raises(Ask::Session::NotFoundError) { sink.emit(:tool_completed, event: event) }
  end

  def test_sink_events_survive_export_import_round_trip
    @sink.emit(:tool_completed, event: completed_event)
    payload = @store.export("s1")

    restored = Ask::Session::Store.new
    restored.import(payload)
    types = restored.events("s1").map(&:type)
    assert_equal ["session.created", "tool.completed"], types
  end
end

class SinkInterfaceTest < Minitest::Test
  def setup
    @host = Ask::Session::Host.new
    @host.create(id: "s1")
    @sink = Ask::Session::Sink.new(host: @host, session_id: "s1")
  end

  def test_listening_true_for_mapped_types
    assert @sink.listening?(:tool_started)
    assert @sink.listening?(:tool_completed)
    assert @sink.listening?(:tool_failed)
    assert @sink.listening?(:tool_cancelled)
    assert @sink.listening?(:tool_timed_out)
  end

  def test_listening_false_for_unknown_types
    refute @sink.listening?(:custom_event)
    refute @sink.listening?("tool_started_string_mismatch")
  end

  def test_host_sink_factory
    sink = @host.sink("s1", trace_id: "t1")
    assert_instance_of Ask::Session::Sink, sink
    assert_same @host, sink.host
    assert_equal "s1", sink.session_id
    assert_equal "t1", sink.trace_id
  end
end
