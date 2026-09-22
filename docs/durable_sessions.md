# Durable Sessions with SQLite

This guide covers persisting sessions across process restarts with
`Ask::Session::ProviderStore`, backed by the SQLite adapter from the optional
[ask-state-providers](https://github.com/ask-rb/ask-state-providers) gem.

Use this whenever session history must survive restarts — production hosts,
background workers, anything that reopens the same database later. Restart
durability works with any adapter that responds to `get`, `set`, and `delete`;
sharing sessions safely across processes additionally requires the adapter to
implement `acquire_lock` / `release_lock`. `ProviderStore` implements the same
API as the in-memory `Store`, so a `Host` built over it needs no other changes.

## Prerequisites and Setup

- Everything from [In-Memory Sessions](in_memory_sessions.md)
- `gem "ask-state-providers"` in **your** application's Gemfile (it is an
  optional integration — ask-session keeps zero runtime dependencies and only
  duck-types the adapter)

The adapter must respond to `get`, `set`, and `delete`. Adapters that also
expose `acquire_lock` / `release_lock` (the SQLite adapter does) additionally
get cross-process locking. An adapter missing the core methods raises
`ArgumentError` at construction.

## Example

```ruby
require "ask-session"
require "ask-state-providers"

def open_host
  adapter = Ask::State::Providers::SQLite.new(path: "sessions.db")
  store = Ask::Session::ProviderStore.new(adapter: adapter)
  [adapter, Ask::Session::Host.new(store: store)]
end

adapter, host = open_host
host.create(id: "s1", metadata: { user: "alice" })
host.send_message("s1", content: "hello")
host.close("s1", reason: "done")
adapter.close

# Later — same file, new process:
adapter, host = open_host
host.session("s1").status # => :closed
host.session("s1").version # => 3
host.events("s1").map(&:type)
# => ["session.created", "message.added", "session.ended"]
adapter.close
```

## Expected Behavior and Trade-offs

- **Storage layout.** Each session persists under namespaced keys —
  `ask.session:record:<id>`, `ask.session:events:<id>` — alongside an index key
  (`ask.session:index`) and a store lock key. Serialization is JSON with
  symbol-safe encoding (`$ask_sym` tags), so statuses and payload symbols
  round-trip exactly and reduced state stays consistent after a restart.
- **Concurrency.** Every operation runs under an in-process mutex and, when the
  adapter exposes the lock API, under a TTL-bounded cross-process store lock
  (default TTL 10s, bounded wait 5s — an exhausted wait raises
  `Ask::Session::ConcurrencyError`). Adapters without lock methods fall back to
  the in-process mutex alone. Locks serialize; they do not merge — stale
  `expected_sequence` writers still fail with `ConcurrencyError`.
- **Optional dependency.** `ProviderStore` requires nothing beyond the
  `get`/`set`/`delete` contract; ask-state-providers is installed by your
  application, never pulled in by this gem. Other ask-state-providers backends
  honor the same contract; this gem's test suite exercises SQLite only.
- **Same lifecycle guards.** Because a `Host` sits on top exactly as with the
  in-memory store, closed/aborted transitions and sequence checks behave the
  same — see [In-Memory Sessions](in_memory_sessions.md).
- **Write shape.** Appending an event rewrites that session's event list under
  the store lock; fine for session-sized histories, not a log-structured store.

## Next Steps

[Subscriptions and Replay](subscriptions_and_replay.md) — stream a durable
session's events live and resume from a sequence cursor.
