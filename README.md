# Ask::Session

Event-sourced session state for the [ask-rb](https://github.com/ask-rb) ecosystem.

## Installation

Requires Ruby 3.2+.

```ruby
gem "ask-session"
```

## Overview

Ask::Session provides the foundational value objects and stores for event-sourced session management in ask-rb. It defines immutable records, event envelopes, a concurrency-safe in-memory store, a durable provider-backed store for restart-safe sessions, a replayable host with subscriptions, and a state reducer.

### Core Types

- **`Record`** — immutable snapshot of a session: `id`, `status`, `metadata`, `created_at`, `updated_at`, `version`.
- **`Event`** — immutable event envelope: `session_id`, `seq`, `type`, `payload`, `trace_id`, `causation_id`, `created_at`.

### Serialization

`Record` and `Event` support portable JSON serialization via `to_h`/`from_h` and the `Codec` module:

```ruby
# Hash round-trip
record = Ask::Session::Record.create(id: "s1", status: :active, metadata: { key: "val" })
hash = record.to_h          # => { id: "s1", status: :active, ..., created_at: <ISO8601>, version: 0 }
restored = Ask::Session::Record.from_h(hash)

# JSON via Codec
json = Ask::Session::Codec.dump_record(record)
record = Ask::Session::Codec.load_record(json)

# Events work the same way
event = Ask::Session::Event.create(session_id: "s1", seq: 1, type: "session.created")
json = Ask::Session::Codec.dump_event(event)
event = Ask::Session::Codec.load_event(json)
```

Malformed JSON or missing required fields raise `Ask::Session::SerializationError`.

### Store

In-memory event store with optimistic concurrency control:

```ruby
store = Ask::Session::Store.new

# Create a session
store.create(id: "sess_001")

# Append events with expected sequence
event = Ask::Session::Event.new(
  session_id: "sess_001", seq: 1, type: "session.created",
  payload: { status: :active }, created_at: Time.now
)
store.append_event(event, expected_sequence: 0)

# Load session events
events = store.events_after("sess_001", after_seq: 0)

# Get all events for a session (frozen)
events = store.events("sess_001")

# Export/import for portability (all sessions)
data = store.export
new_store = Ask::Session::Store.new
new_store.import(data)

# Export a single session into a fresh store
single = store.export("sess_001")
fresh = Ask::Session::Store.new
fresh.import(single)

# Rebuild session state from events
record = store.state("sess_001")
record.status  # => :active
record.version # => 1
```

### ProviderStore (durable)

`ProviderStore` is the durable counterpart to `Store`: same API (`create`, `load`, `load!`, `list`, `append_event`, `events`, `events_after`, `current_sequence`, `state`, `export`/`import`), but persisted through any adapter that responds to `get`, `set`, and `delete`. The [ask-state-providers](https://github.com/ask-rb/ask-state-providers) adapters (SQLite, Redis, Postgres, MySQL) work out of the box:

```ruby
require "ask-state-providers"

adapter = Ask::State::Providers::SQLite.new(path: "sessions.db")
host = Ask::Session::Host.new(store: Ask::Session::ProviderStore.new(adapter: adapter))

host.create(id: "s1", metadata: { user: "alice" })
host.send_message("s1", content: "hello")
host.close("s1", reason: "done")
adapter.close

# Later — same file, new process:
adapter = Ask::State::Providers::SQLite.new(path: "sessions.db")
host = Ask::Session::Host.new(store: Ask::Session::ProviderStore.new(adapter: adapter))
host.session("s1") # => reduced Record with status: :closed, version: 3
host.events("s1")  # full history survives the restart
```

Each session's record and event list persist under namespaced keys (`ask.session:record:*`, `ask.session:events:*`) alongside a session index, using JSON with symbol-safe encoding so statuses and payload symbols round-trip exactly.

When the adapter exposes the provider lock API (`acquire_lock` / `release_lock`), every operation also runs under a cross-process store lock so read-modify-write sequences stay atomic across processes; exhausting the lock wait budget raises `Ask::Session::ConcurrencyError`. Adapters without lock methods fall back to an in-process mutex. Stale `expected_sequence` writers still fail with `ConcurrencyError` — locks serialize, they do not merge.

ask-session keeps zero runtime dependencies: `ProviderStore` duck-types the adapter, so `ask-state-providers` is an optional integration, not a dependency of this gem.

### State Reducer

Rebuild session state from event history:

```ruby
events = [
  Ask::Session::Event.new(session_id: "s1", seq: 1, type: "session.created",
    payload: { status: :active }, created_at: Time.now),
  Ask::Session::Event.new(session_id: "s1", seq: 2, type: "message.added",
    payload: { role: :user, content: "hello" }, created_at: Time.now)
]

record = Ask::Session::State.reduce("s1", events)
record.status  # => :active
record.version # => 2
```

### Host

Replayable session host with publish-subscribe:

```ruby
store = Ask::Session::Store.new
host = Ask::Session::Host.new(store: store)

# Create a session
record = host.create(id: "s1", metadata: { user: "alice" })
record.status # => :active

# Send messages
event = host.send_message("s1", content: "hello")
event.type # => "message.added"

# Query
host.session("s1")  # => reduced Record
host.list           # => [Record, ...]
host.events("s1")   # => [Event, ...]

# Subscribe with replay
sub = host.subscribe("s1")
event = sub.next(timeout: 1.0)  # returns event or nil on timeout
sub.each { |e| puts e.type }    # yields until closed
sub.close

# Close or abort
host.close("s1", reason: "done")
host.abort("s1", reason: "error")
```

Invalid transitions (send to closed/aborted, close twice) raise `Ask::Session::InvalidTransitionError`.

#### Generic event append

`Host#append` lets adapters record arbitrary event types (tool calls, vendor webhooks, custom lifecycle events) without coupling ask-session to any protocol or agent gem:

```ruby
# Append a tool event
event = host.append("s1", type: "tool.started", payload: { tool: "search" })

# Append with trace correlation
event = host.append("s1",
  type: "vendor.webhook.received",
  payload: { raw: body },
  trace_id: "trace_abc",
  causation_id: originating_event.trace_id
)
```

Every appended event advances the session's reduced `version` and `updated_at`, regardless of event type. Appends to closed or aborted sessions raise `InvalidTransitionError`. Adapters use `append` instead of `send_message` when the event type is not `message.added` — this keeps ask-session free of protocol and agent dependencies.

#### Runtime tool-lifecycle sink

`Ask::Session::Sink` is the boundary to ask-runtime's event-sink contract. Executors in ask-agent, ask-mcp, and ask-sandbox-providers report tool lifecycle through `ExecutionContext#event_sink` by calling `emit(event_type, event:)` — point that sink at a session host and tool history becomes part of the event-sourced session:

```ruby
host = Ask::Session::Host.new
host.create(id: "s1")

sink = host.sink("s1", trace_id: "trace_abc")
# pass `sink` as ExecutionContext's event_sink; runtime emits then record:
#   :tool_started   -> tool.started
#   :tool_completed -> tool.completed
#   :tool_failed    -> tool.failed
#   :tool_cancelled -> tool.cancelled
#   :tool_timed_out -> tool.timed_out

host.events("s1").last.payload
# => { tool_name: "bash", tool_call_id: "tc_1", input: { "cmd" => "ls" }, turn: 3 }
```

Terminal events carry `outcome` (`:completed`/`:failed`/`:cancelled`/`:timed_out`), `duration` in seconds, `error` when present, and `output` when the runtime result exposes one. The sink duck-types the runtime events' public readers, so ask-session keeps zero runtime dependencies.

Guards: an event correlated to a different session raises `Ask::Session::SessionMismatchError`; appends to closed/aborted sessions are dropped (terminal sessions stop recording without failing an in-flight tool run); missing sessions raise `NotFoundError`; unknown event types are ignored.

```ruby
sink = Ask::Session::Sink.new(host: host, session_id: "s1", causation_id: originating.trace_id)
sink.listening?(:tool_started) # => true
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Create a Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.
