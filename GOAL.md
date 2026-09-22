# Ask Session Foundation

## What we're building

Make `ask-session` the authoritative session state layer for the Ask ecosystem:
event-sourced records, immutable events, an in-memory store with concurrency
guardrails, and a state reducer that reconstructs session snapshots from history.

## How this works (the rules of engagement)

- Every behavior change is test-first and must leave the full suite green.
- Use stdlib only — no database, transport, or gem dependencies yet.
- Immutable value objects for `Record` and `Event`; no shared mutable state.
- Concurrency errors must raise a dedicated, named exception on sequence mismatch.
- IDs and timestamps are deterministic when supplied, auto-generated otherwise.
- This is a living document: update it when implementation discoveries change
  the scope.

## Design decisions (made so far)

- `Ask::Session::Record` is the immutable snapshot of a session: `id`, `status`,
  `metadata`, `created_at`, `updated_at`, `version`.
- `Ask::Session::Event` is the immutable event envelope: `session_id`, `seq`,
  `type`, `payload`, `trace_id`, `causation_id`, `created_at`.
- `Ask::Session::Store` is an in-memory store with `create`, `load`, `list`,
  `append_event`, `events_after`, and `current_sequence`.
- `Ask::Session::State` is a pure reducer that rebuilds `Record` from events and
  handles `session.created`, `session.status_changed`, `session.ended`,
  `session.aborted`, `message.added`, and `tool.completed`. Unknown event types
  remain in history without crashing.
- `Ask::Session::Host` is a replayable session host with publish-subscribe.
  It wraps Store, creates events, enforces transitions, and delivers events to
  subscribers atomically under a single lock.
- `Ask::Session::Subscription` is a thread-safe subscription backed by a Queue
  and Mutex. `next` is the primary method using `Timeout.timeout` with
  `Queue#pop`; `wait` is an alias for backward compatibility. `each` yields
  until closed (blocking `next`, no poll window), and `close` pushes a sentinel
  so a blocked `next`/`each` wakes with `nil`.
- `Ask::Session::Sink` is the ask-runtime event-sink boundary. It implements
  the producer side of `ExecutionContext#event_sink` —
  `emit(event_type, event:)` — and maps the five runtime tool lifecycle types
  (`:tool_started`, `:tool_completed`, `:tool_failed`, `:tool_cancelled`,
  `:tool_timed_out`) onto session events `tool.started` / `tool.completed` /
  `tool.failed` / `tool.cancelled` / `tool.timed_out` via `Host#append`.
  Extraction is duck-typed over the runtime events' public readers, so the
  gem keeps zero runtime dependencies. Cross-session events raise
  `SessionMismatchError`; appends to terminal (closed/aborted) sessions are
  dropped so in-flight tool runs never fail because recording ended; unknown
  event types are ignored for forward compatibility.
- `Host#sink(session_id, trace_id:, causation_id:)` is the factory that binds
  a `Sink` to a host and session.

## Cross-gem boundary notes (discovered)

- `ask-agent` declares `ask-session >= 0.1.0` and its `SessionAdapter` calls
  `create`, `session`, `events`, `send_message`, `append`, `close`, `abort` —
  all present and covered. One drift lives on the ask-agent side: `resume`
  guards with `raise ArgumentError unless host.session(id)`, but `Host#session`
  raises `Ask::Session::NotFoundError` for missing sessions (the tested,
  committed contract here). The adapter should rescue/re-raise; not changed
  in this repository.
- `ask-runtime`, `ask-mcp`, and `ask-sandbox-providers` all emit tool
  lifecycle through `context.event_sink.emit(type, event:)`. Nothing in the
  ecosystem bridged that stream into durable session state — `Sink` is that
  bridge (Phase 5).
- Wire vocabulary (`ask-session-protocol`) stays out of this gem: `Sink`
  records session-state events only; translation to the canonical wire
  envelope belongs to the host/protocol layer.

## Phases with task lists

| Phase | Tasks |
| --- | --- |
| Skeleton | - [x] Create gem structure, GOAL.md, CI, and setup scripts. |
| Contract | - [x] Write Minitest specs for Record, Event, Store, and State. |
| Implementation | - [x] Implement value objects, in-memory store, and state reducer. |
| Verification | - [x] Run full suite green on Ruby 3.2+. |
| Commit | - [x] Review diff, stage, and commit the complete slice. |
| Serialization | - [x] Add Record/Event to_h/from_h, Codec, Store export/import, SerializationError. |
| Phase 2 Hardening | - [x] Add Store#state, single-session export, atomic import, frozen events_after. |
| Phase 3 Host | - [x] Add Host (create, send_message, close, abort, subscribe, publish-subscribe). |
| | - [x] Add Subscription (next, wait alias, close, each, replay). |
| | - [x] Add InvalidTransitionError for illegal state transitions. |
| Phase 4 Hardening | - [x] Host#initialize default store, Host#list with State.reduce, Host#create under mutex, Subscription#next with Timeout.timeout, Host#publish prunes closed subs. |
| Phase 4b Fix | - [x] Subscription#each blocks until close instead of timing out after 0.1s of silence (restores documented "yields until closed"). |
| Phase 5 Runtime boundary | - [x] Add Ask::Session::Sink mapping runtime tool lifecycle emits to session events (duck-typed, stdlib only). |
| | - [x] Add SessionMismatchError; terminal sessions drop events; NotFound still raises. |
| | - [x] Add Host#sink factory; export/import and subscriber coverage for sink events. |
| | - [x] Verify: focused + full suite, gem build, diff review, commit. |

## Definition of done

1. A clean checkout of `ask-session` runs its tests on Ruby 3.2+.
2. `Ask::Session::Store` enforces expected_sequence and raises on mismatch.
3. `Ask::Session::State` reconstructs session state from a list of events.
4. Unknown event types are preserved without raising or corrupting state.
5. The gem can be built with `gem build` and has no external runtime dependencies.
6. A runtime executor can wire `ExecutionContext#event_sink` to
   `host.sink(id)` and have tool lifecycle recorded as session events.
7. `Subscription#each` iterates until close regardless of event silence.
