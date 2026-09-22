# Tool Lifecycle through Host#sink

This guide covers recording ask-runtime tool lifecycle into a session with
`Host#sink` and `Ask::Session::Sink` — the bridge that implements the producer
side of ask-runtime's `ExecutionContext#event_sink` contract.

Use this when executors in ask-agent, ask-mcp, or ask-sandbox-providers report
tool lifecycle (`emit(event_type, event:)`) and you want that history to become
part of the event-sourced session. The sink duck-types the runtime events'
public readers, so ask-session keeps zero runtime dependencies on ask-runtime.

These provider-neutral lifecycle events are not the same vocabulary as the
ask-session-protocol wire events (`tool.use`, `tool.delta`, and `tool.result`).
Protocol-facing integrations translate agent events at their boundary (for
example, ask-app-server's `EventTranslator`); ask-session itself does not
depend on that protocol. For a given tool execution, use one persistence
producer per host: attaching both this runtime sink and an adapter that
persists protocol-facing tool events records two lifecycle histories.

## Prerequisites and Setup

- Everything from [In-Memory Sessions](in_memory_sessions.md)
- The target session must already exist (`host.create`) — emitting against a
  missing session raises `Ask::Session::NotFoundError`
- On the producer side, any object responding to
  `emit(event_type, event:)` can act as the `ExecutionContext#event_sink`; pass
  the sink `Host#sink` returns

## Example

```ruby
require "ask-session"

host = Ask::Session::Host.new
host.create(id: "s1")

sink = host.sink("s1", trace_id: "trace_abc")
sink.listening?(:tool_started) # => true

# Stand-ins for ask-runtime's immutable event types (duck-typed readers only).
ToolCall     = Struct.new(:input, :state, :session_id, keyword_init: true)
ToolResult   = Struct.new(:output, :error_message, keyword_init: true)
RuntimeEvent = Struct.new(:tool_name, :tool_call_id, :tool_call, :tool_result,
                          :duration, :error, :execution_context, :session_id,
                          keyword_init: true)

sink.emit(:tool_started, event: RuntimeEvent.new(
  tool_name: "bash", tool_call_id: "tc_1",
  tool_call: ToolCall.new(input: { "cmd" => "ls" })
))

sink.emit(:tool_completed, event: RuntimeEvent.new(
  tool_name: "bash", tool_call_id: "tc_1",
  tool_call: ToolCall.new(input: { "cmd" => "ls" }, state: :completed),
  tool_result: ToolResult.new(output: "file.txt"),
  duration: 0.42
))

started, completed = host.events("s1").last(2)
started.type    # => "tool.started"
started.payload # => { tool_name: "bash", tool_call_id: "tc_1",
                #      input: { "cmd" => "ls" } }

completed.type    # => "tool.completed"
completed.payload # => { tool_name: "bash", tool_call_id: "tc_1",
                #      outcome: :completed, duration: 0.42, output: "file.txt" }
completed.trace_id # => "trace_abc" (bound when the sink was built)

# With an execution context on the event, `turn` is included too.
```

In a real wiring, build the execution context with the sink:

```ruby
context = Ask::Runtime::ExecutionContext.new(session_id: "s1", event_sink: sink)
# runtime emits (:tool_started, :tool_completed, ...) now record as session events
```

## Event Mapping

| Runtime event      | Session event type | Payload highlights                          |
| ------------------ | ------------------ | ------------------------------------------- |
| `:tool_started`    | `tool.started`     | `tool_name`, `tool_call_id`, `input`, `turn` |
| `:tool_completed`  | `tool.completed`   | `outcome`, `duration`, `output`, `error`     |
| `:tool_failed`     | `tool.failed`      | `outcome`, `duration`, `error`               |
| `:tool_cancelled`  | `tool.cancelled`   | `outcome`, `duration`, `error`               |
| `:tool_timed_out`  | `tool.timed_out`   | `outcome`, `duration`, `error`               |

Terminal events carry `outcome` (the `tool_call.state` vocabulary when present,
otherwise `:completed` / `:failed` / `:cancelled` / `:timed_out`), `duration` in
seconds, and `error` when a failure or cancellation reason is available. Nil
values are omitted. Every recorded event goes through `Host#append`, so it
advances the session's reduced `version` and appears on subscriptions.

## Expected Behavior and Trade-offs

- **Guards.** An event correlated to a different session (via `tool_call`,
  `execution_context`, or `session_id`) raises
  `Ask::Session::SessionMismatchError` — never cross-write. Emitting a mapped
  type without `event:` raises `ArgumentError`. Unknown event types are ignored
  (`listening?` reports what the sink records), so additive runtime growth is
  safe.
- **Terminal sessions drop, not fail.** Appends to a closed or aborted session
  are silently dropped: recording stops, but an in-flight tool run is never
  failed by the boundary. Missing sessions still raise `NotFoundError` — that
  is a wiring bug, not a lifecycle race.
- **Correlation is fixed at construction.** `trace_id` / `causation_id` passed
  to `Host#sink` are stamped on every event it appends; build one sink per
  trace (or pass `causation_id: originating.trace_id`) for causal chains.
- **Duck-typed, not linked.** Payload extraction uses public readers only — no
  ask-runtime classes are required, and extra runtime fields are ignored.

## Next Steps

[Export and Import](export_import.md) — move a session's full history,
tool events included, into another store.
