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
