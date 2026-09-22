# Export and Import

This guide covers moving session history between stores with `Store#export` /
`Store#import` and their `ProviderStore` counterparts — backups, extracting a
single session, or migrating an in-memory store to durable storage.

Use this when you need portability: hand a session's record and events to
another process, seed a database from a test fixture, or promote in-memory
history to SQLite. For ongoing durable storage, prefer
[Durable Sessions with SQLite](durable_sessions.md) over repeated export/import.

## Prerequisites and Setup

- Everything from [In-Memory Sessions](in_memory_sessions.md)
- Keep a reference to the store when you build your own host —
  `Host` does not expose its store, so construct it yourself:

```ruby
store = Ask::Session::Store.new
host  = Ask::Session::Host.new(store: store)
```

- For a durable target, additionally install `ask-state-providers` as in
  [Durable Sessions with SQLite](durable_sessions.md)

## Example

```ruby
require "ask-session"

# Source: build history through a Host over an in-memory store.
store = Ask::Session::Store.new
host = Ask::Session::Host.new(store: store)
host.create(id: "s1", metadata: { user: "alice" })
host.send_message("s1", content: "hello")
host.close("s1", reason: "done")

# Export one session (or call store.export with no argument for all sessions).
payload = store.export("s1")
# => { sessions: [ { id: "s1", status: :closed, ... } ],
#      events:  [ { session_id: "s1", seq: 1, ... }, ... ] }

# Import into a fresh in-memory store — keep the payload a Ruby Hash.
fresh = Ask::Session::Store.new
fresh.import(payload)
fresh.state("s1").status # => :closed
fresh.events("s1").size   # => 3

# Or import straight into durable storage:
require "ask-state-providers"
adapter = Ask::State::Providers::SQLite.new(path: "sessions.db")
durable = Ask::Session::ProviderStore.new(adapter: adapter)
durable.import(store.export("s1"))
durable.state("s1").status # => :closed
adapter.close
```

`ProviderStore#export` / `#import` accept the same shapes, so transfers work in
either direction (in-memory ↔ durable).

> **WARNING: Do not JSON-round-trip export payloads.** Plain
> `JSON.generate(store.export)` → `JSON.parse` flattens Symbol values to
> Strings; on re-import a closed session reduces to status `"closed"`, while
> lifecycle guards compare against `:closed` — so a closed session would accept
> writes again, and any `status == :closed` check in your code silently breaks.
> Transfer the Ruby Hash as-is (same process, a Ruby-aware channel, or a format
> that preserves Symbols), or store durably with `ProviderStore`, which uses
> symbol-safe encoding internally.

## Expected Behavior and Trade-offs

- **Shapes.** Export returns `{ sessions: [...], events: [...] }` of plain
  `to_h` hashes for all sessions or a single one (`export("s1")`). Import
  accepts both shapes and symbol or string keys.
- **Validation before mutation.** Import validates the whole payload first: a
  record without an id raises `SerializationError`; an id already in the target
  (or duplicated inside the payload) raises `DuplicateSessionError`; an event
  for an unknown session raises `NotFoundError`; non-contiguous sequences raise
  `ConcurrencyError`. A failed import leaves the target unchanged. Events for
  sessions already in the target are accepted when their sequences continue
  from the current end.
- **Fidelity.** Hash round-trips preserve Symbol statuses and payload values,
  ISO8601 timestamps (parsed back to `Time`), and frozen records/events —
  reduced state after import matches the source.
- **Portability vs. durability.** Export/import is for one-shot transfers;
  live durability (locking, restart survival) is `ProviderStore`'s job. The two
  compose: export from either store, import into either store.

## Next Steps

Return to the [Guides index](index.md) to pick up another workflow.
