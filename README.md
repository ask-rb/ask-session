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

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Create a Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.
