# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-22

### Added

- `Ask::Session::Record` — immutable value object for session snapshots.
- `Ask::Session::Event` — immutable event envelope with sequence, type, and causation.
- `Ask::Session::Store` — in-memory store with concurrency guardrails.
- `Ask::Session::State` — pure reducer that reconstructs session state from events.
- `Ask::Session::ConcurrencyError` — dedicated error for sequence mismatches.
- `Ask::Session::SerializationError` — dedicated error for malformed/missing-field JSON.
- `Ask::Session::NotFoundError` — dedicated error when a session id does not exist.
- `Ask::Session::DuplicateSessionError` — dedicated error when creating or importing a session id that already exists.
- `Store#load!` — loads a session or raises `NotFoundError`.
- `Store#current_sequence` — current event count for a session.
- `Record#to_h` / `Record.from_h` — portable hash serialization with ISO8601 timestamps.
- `Event#to_h` / `Event.from_h` — portable hash serialization with ISO8601 timestamps.
- `Ask::Session::Codec` — JSON dump/load for Record and Event.
- `Store#events` — returns a frozen array of all events for a session.
- `Store#export` / `Store#import` — full session portability with duplicate and sequence validation.
- `Store#state(session_id)` — reconstructs session state from stored events via the reducer.
- `Store#export(session_id)` — exports a single session payload for targeted import.
- `Store#import` — accepts both all-sessions and single-session shapes; validates atomically before mutating.
- `Store#events_after` — now returns a frozen array snapshot.
- `Ask::Session::Host` — replayable session host with create, session, list, events, send_message, close, abort, subscribe, and publish-subscribe.
- `Host#append(session_id, type:, payload:, trace_id:, causation_id:)` — generic event append for arbitrary event types (tool calls, vendor webhooks, custom lifecycle events) without coupling ask-session to any protocol or agent gem.
- `Ask::Session::ProviderStore` — durable store backed by any adapter responding to `get`, `set`, and `delete` (e.g. the ask-state-providers SQLite/Redis/Postgres/MySQL adapters): namespaced record/event keys, a session index, and symbol-safe JSON round-trip so sessions, events, and reduced state survive process restarts when a `Host` is built over it.
- `ProviderStore` cross-process locking — when the adapter exposes `acquire_lock`/`release_lock`, every public operation runs under a TTL-bounded store lock with bounded retry (an exhausted wait budget raises `ConcurrencyError`); adapters without lock methods fall back to an in-process mutex. Stale `expected_sequence` writers still fail with `ConcurrencyError` — locks serialize, they do not merge.
- `ProviderStore#export` / `ProviderStore#import` — portability parity with `Store`, accepting both all-sessions and single-session shapes with atomic validation before mutating.
- `Ask::Session::Subscription` — thread-safe subscription with next (Timeout.timeout-backed), wait (alias for next), close, each, and replay.
- `Ask::Session::InvalidTransitionError` — dedicated error for illegal state transitions (send to closed/aborted, close/abort twice).
- `Ask::Session::Sink` — ask-runtime event-sink bridge: implements `emit(event_type, event:)` and maps `:tool_started` / `:tool_completed` / `:tool_failed` / `:tool_cancelled` / `:tool_timed_out` to `tool.started` / `tool.completed` / `tool.failed` / `tool.cancelled` / `tool.timed_out` session events via `Host#append`. Duck-typed extraction (no ask-runtime dependency); payloads carry `tool_name`, `tool_call_id`, `input` (started), `outcome`, `duration`, `error`, `output` (terminal), and `turn` when present.
- `Ask::Session::SessionMismatchError` — dedicated error when a sink receives an event correlated to a different session.
- `Host#sink(session_id, trace_id:, causation_id:)` — factory that binds a `Sink` to a host and session.

### Changed

- `Host#initialize` now accepts `store:` with a default of `Store.new`.
- `Host#list` returns `State.reduce` records so close/abort status is reflected.
- `Host#create` performs store create, event append, and publish atomically under `@mutex`.
- `Host#publish` prunes closed subscriptions from its per-session list.
- `Subscription#next` is the primary method using `Queue#pop` wrapped in `Timeout.timeout`; `wait` is aliased to `next` for backward compatibility.
- `Subscription#close` pushes a sentinel so a blocked `next` wakes with `nil` instead of relying on sleep polling.
- `Subscription#each` now blocks until close instead of timing out after 0.1s of silence — it yields across quiet periods and only stops when the subscription is closed (restores the documented "yields until closed" contract).
- `Sink#emit` drops (does not raise) appends to closed or aborted sessions so in-flight tool runs are never failed by the recording boundary; missing sessions still raise `NotFoundError`.
