# Ask Session Foundation

## What we're building

Make `ask-session` the authoritative session state layer for the Ask ecosystem:
event-sourced records, immutable events, an in-memory store with concurrency
guardrails, and a state reducer that reconstructs session snapshots from history.

## How this works (the rules of engagement)

- Every behavior change is test-first and must leave the full suite green.
- Use stdlib only — no database, transport, or ask-agent integration yet.
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
  handles `session.created`, `session.status_changed`, `message.added`, and
  `tool.completed`. Unknown event types remain in history without crashing.

## Phases with task lists

| Phase | Tasks |
| --- | --- |
| Skeleton | - [x] Create gem structure, GOAL.md, CI, and setup scripts. |
| Contract | - [x] Write Minitest specs for Record, Event, Store, and State. |
| Implementation | - [x] Implement value objects, in-memory store, and state reducer. |
| Verification | - [x] Run full suite green on Ruby 3.2+. |
| Commit | - [x] Review diff, stage, and commit the complete slice. |
| Serialization | - [x] Add Record/Event to_h/from_h, Codec, Store export/import, SerializationError. |

## Definition of done

1. A clean checkout of `ask-session` runs its tests on Ruby 3.2+.
2. `Ask::Session::Store` enforces expected_sequence and raises on mismatch.
3. `Ask::Session::State` reconstructs session state from a list of events.
4. Unknown event types are preserved without raising or corrupting state.
5. The gem can be built with `gem build` and has no external runtime dependencies.
