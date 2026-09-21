# Ask::Session

Event-sourced session state for the [ask-rb](https://github.com/ask-rb) ecosystem.

## Installation

```ruby
gem "ask-session"
```

## Overview

Ask::Session provides the foundational value objects and in-memory store for event-sourced session management in ask-rb. It defines immutable records, event envelopes, a concurrency-safe store, and a state reducer.

### Core Types

- **`Record`** — immutable snapshot of a session: `id`, `status`, `metadata`, `created_at`, `updated_at`, `version`.
- **`Event`** — immutable event envelope: `session_id`, `seq`, `type`, `payload`, `trace_id`, `causation_id`, `created_at`.

### Serialization

`Record` and `Event` support portable JSON serialization via `to_h`/`from_h` and the `Codec` module:

```ruby
# Hash round-trip
record = Ask::Session::Record.create(id: "s1", status: :active, metadata: { key: "val" })
hash = record.to_h          # => { id: "s1", status: :active, ..., created_at: "2026-01-01T00:00:00Z" }
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

# Export a single session
single = store.export("sess_001")
new_store.import(single)

# Rebuild session state from events
record = store.state("sess_001")
record.status  # => :active
record.version # => 2
```

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

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Create a Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.
