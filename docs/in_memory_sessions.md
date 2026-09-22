# In-Memory Sessions

This guide covers running event-sourced sessions in a single process with
`Ask::Session::Host` over the in-memory `Ask::Session::Store`.

Use this when sessions do not need to survive process restarts: development,
tests, short-lived tools, or learning the API before wiring a durable store.
When history must outlive the process, follow
[Durable Sessions with SQLite](durable_sessions.md) instead — the `Host` API is
identical over either store.

## Prerequisites and Setup

- Ruby 3.2+
- `gem "ask-session"` in your Gemfile, then `require "ask-session"`

No other dependencies. `Host.new` defaults to a fresh in-memory `Store`, so you
can construct a host directly.

## Example

```ruby
require "ask-session"

host = Ask::Session::Host.new # uses an in-memory Ask::Session::Store

created = host.create(id: "s1", metadata: { user: "alice" })
created.status  # => :active
created.version # => 1

host.send_message("s1", content: "hello")
host.append("s1", type: "vendor.webhook.received", payload: { ok: true })

snapshot = host.session("s1")
snapshot.status     # => :active
snapshot.version    # => 3
snapshot.metadata   # => { user: "alice" }

host.list                                   # => [snapshot, ...]
host.events("s1").map(&:type)
# => ["session.created", "message.added", "vendor.webhook.received"]

closed = host.close("s1", reason: "done")
closed.status # => :closed

begin
  host.send_message("s1", content: "too late")
rescue Ask::Session::InvalidTransitionError => e
  e.message # => "Session s1 is closed"
end
```

## Expected Behavior and Trade-offs

- **Process-local.** Everything lives in process memory and is lost on exit.
  Nothing is written to disk.
- **Writes are serialized.** `Host` appends under an internal mutex, and the
  store enforces optimistic concurrency: a direct `Store#append_event` with a
  stale `expected_sequence` raises `Ask::Session::ConcurrencyError`.
- **Ids and duplicates.** `create` generates a `sess_…` id when none is given;
  creating an existing id raises `Ask::Session::DuplicateSessionError`.
- **Reduced state.** `session`, `list`, `close`, and `abort` return a frozen
  `Record` rebuilt by `State.reduce` — every accepted event advances its
  `version` and `updated_at`, whatever the event type. Records and events are
  frozen, with deeply frozen payloads.
- **Lifecycle guards.** `send_message`, `append`, `close`, and `abort` on a
  closed or aborted session raise `Ask::Session::InvalidTransitionError`.
- **Both entry points are supported.** Use `Host` for the guarded,
  publish-subscribe workflow; use `Store` directly when you need raw
  `append_event` control.

## Next Steps

[Durable Sessions with SQLite](durable_sessions.md) — keep the same `Host` code
and make sessions survive restarts.
