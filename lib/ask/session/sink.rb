# frozen_string_literal: true

module Ask
  module Session
    # Bridge from the ask-runtime event-sink contract to a session Host.
    #
    # ask-runtime executors (ask-agent, ask-mcp, ask-sandbox-providers)
    # report tool lifecycle through +ExecutionContext#event_sink+ by calling
    # <tt>emit(event_type, event: event)</tt> with the immutable runtime
    # events (+:tool_started+, +:tool_completed+, +:tool_failed+,
    # +:tool_cancelled+, +:tool_timed_out+). This sink implements that
    # producer side and appends the mapped session events through
    # +Host#append+, so tool history becomes part of the event-sourced
    # session without ask-session depending on ask-runtime.
    #
    #   sink = host.sink("s1", trace_id: current_trace_id)
    #   context = Ask::Runtime::ExecutionContext.new(session_id: "s1", event_sink: sink)
    #
    # Mapping (runtime symbol -> session event type):
    #
    #   :tool_started    -> "tool.started"
    #   :tool_completed  -> "tool.completed"
    #   :tool_failed     -> "tool.failed"
    #   :tool_cancelled  -> "tool.cancelled"
    #   :tool_timed_out  -> "tool.timed_out"
    #
    # Payloads are extracted duck-typed from the event's public readers
    # (+tool_name+, +tool_call_id+, +duration+, +error+, +reason+,
    # +tool_call+, +execution_context+, +tool_result+), so no runtime
    # classes are required. Nil values are omitted.
    #
    # Terminal events carry +outcome+ (+:completed+, +:failed+,
    # +:cancelled+, +:timed_out+ — the ToolCall state vocabulary),
    # +duration+ in seconds, and +error+ when a failure or cancellation
    # reason is available.
    #
    # Guards:
    # - A correlated event whose session id differs from the sink's
    #   session raises SessionMismatchError (never cross-write sessions).
    # - Appends to a closed or aborted session are dropped silently:
    #   terminal sessions stop recording, but a tool run already in
    #   flight must not fail because recording ended.
    # - A mapped type emitted without an +event:+ raises ArgumentError.
    # - Unknown event types are ignored (additive runtime growth).
    # - Missing sessions still raise NotFoundError (wiring bug).
    class Sink
      MAPPING = {
        tool_started: "tool.started",
        tool_completed: "tool.completed",
        tool_failed: "tool.failed",
        tool_cancelled: "tool.cancelled",
        tool_timed_out: "tool.timed_out"
      }.freeze

      DEFAULT_OUTCOMES = {
        "tool.completed" => :completed,
        "tool.failed" => :failed,
        "tool.cancelled" => :cancelled,
        "tool.timed_out" => :timed_out
      }.freeze

      attr_reader :host, :session_id, :trace_id, :causation_id

      def initialize(host:, session_id:, trace_id: nil, causation_id: nil)
        @host = host
        @session_id = session_id
        @trace_id = trace_id
        @causation_id = causation_id
      end

      # Producer side of the ask-runtime EventSink contract.
      #
      # @param event_type [Symbol, String] runtime event name
      # @param event [Object, nil] the runtime event (required for mapped types)
      # @return [self]
      # @raise [ArgumentError] when a mapped type is emitted without an event
      # @raise [SessionMismatchError] when the event correlates to another session
      # @raise [NotFoundError] when the sink's session does not exist
      def emit(event_type, event: nil)
        type = MAPPING[coerce(event_type)]
        return self unless type

        raise ArgumentError, "event: is required for #{event_type.inspect}" if event.nil?

        mismatched = conflicting_session_id(event)
        if mismatched
          raise SessionMismatchError,
                "Event for session #{mismatched.inspect} cannot be recorded in session #{@session_id.inspect}"
        end

        append(type, event)
        self
      rescue InvalidTransitionError
        self
      end

      # Whether this sink records the given runtime event type.
      def listening?(event_type)
        MAPPING.key?(coerce(event_type))
      end

      private

      def coerce(event_type)
        event_type.respond_to?(:to_sym) ? event_type.to_sym : event_type
      end

      def append(type, event)
        @host.append(
          @session_id,
          type: type,
          payload: build_payload(type, event),
          trace_id: @trace_id,
          causation_id: @causation_id
        )
      end

      def build_payload(type, event)
        payload = {}
        add(payload, :tool_name, read(event, :tool_name))
        add(payload, :tool_call_id, read(event, :tool_call_id))
        add(payload, :turn, turn_of(event))
        add(payload, :input, input_of(event)) if type == "tool.started"

        unless type == "tool.started"
          add(payload, :outcome, outcome_of(type, event))
          add(payload, :duration, read(event, :duration))
          add(payload, :error, error_of(event))
          output = output_of(event)
          add(payload, :output, output) unless output.nil?
        end

        payload
      end

      def add(payload, key, value)
        payload[key] = value unless value.nil?
      end

      def read(object, method)
        object.public_send(method) if object.respond_to?(method)
      end

      def turn_of(event)
        ctx = read(event, :execution_context)
        read(ctx, :turn)
      end

      def input_of(event)
        call = read(event, :tool_call)
        read(call, :input)
      end

      def outcome_of(type, event)
        call = read(event, :tool_call)
        read(call, :state) || DEFAULT_OUTCOMES[type]
      end

      def error_of(event)
        read(event, :error) || read(event, :reason) || begin
          result = read(event, :tool_result)
          read(result, :error_message)
        end
      end

      def output_of(event)
        result = read(event, :tool_result)
        read(result, :output)
      end

      def conflicting_session_id(event)
        found = session_id_from(event)
        found if found && found != @session_id
      end

      def session_id_from(event)
        call = read(event, :tool_call)
        from_call = read(call, :session_id)
        return from_call if from_call

        ctx = read(event, :execution_context)
        from_ctx = read(ctx, :session_id)
        return from_ctx if from_ctx

        read(event, :session_id)
      end
    end
  end
end
