# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- `Ask::Session::Record` — immutable value object for session snapshots.
- `Ask::Session::Event` — immutable event envelope with sequence, type, and causation.
- `Ask::Session::Store` — in-memory store with concurrency guardrails.
- `Ask::Session::State` — pure reducer that reconstructs session state from events.
- `Ask::Session::ConcurrencyError` — dedicated error for sequence mismatches.
- `Ask::Session::SerializationError` — dedicated error for malformed/missing-field JSON.
- `Record#to_h` / `Record.from_h` — portable hash serialization with ISO8601 timestamps.
- `Event#to_h` / `Event.from_h` — portable hash serialization with ISO8601 timestamps.
- `Ask::Session::Codec` — JSON dump/load for Record and Event.
- `Store#events` — returns a frozen array of all events for a session.
- `Store#export` / `Store#import` — full session portability with duplicate and sequence validation.
- `Store#state(session_id)` — reconstructs session state from stored events via the reducer.
- `Store#export(session_id)` — exports a single session payload for targeted import.
- `Store#import` — accepts both all-sessions and single-session shapes; validates atomically before mutating.
- `Store#events_after` — now returns a frozen array snapshot.
- `Ask::Session::Host` — replayable session host with create, send_message, close, abort, subscribe, and publish-subscribe.
- `Ask::Session::Subscription` — thread-safe subscription with next (Timeout.timeout-backed), wait (alias for next), close, each, and replay.
- `Ask::Session::InvalidTransitionError` — dedicated error for illegal state transitions (send to closed/aborted, close/abort twice).

### Changed

- `Host#initialize` now accepts `store:` with a default of `Store.new`.
- `Host#list` returns `State.reduce` records so close/abort status is reflected.
- `Host#create` performs store create, event append, and publish atomically under `@mutex`.
- `Host#publish` prunes closed subscriptions from its per-session list.
- `Subscription#next` is the primary method using `Queue#pop` wrapped in `Timeout.timeout`; `wait` is aliased to `next` for backward compatibility.
- `Subscription#close` pushes a sentinel so a blocked `next` wakes with `nil` instead of relying on sleep polling.
- `Subscription#each` now blocks until close instead of timing out after 0.1s of silence — it yields across quiet periods and only stops when the subscription is closed (restores the documented "yields until closed" contract).
