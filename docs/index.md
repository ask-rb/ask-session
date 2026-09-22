# Ask::Session Guides

These guides cover the task-oriented workflows for Ask::Session, the event-sourced
session state library for the [ask-rb](https://github.com/ask-rb) ecosystem.

Each guide follows the same shape: the task and when to use it, prerequisites and
setup, an end-to-end example, expected behavior and trade-offs, and a next-steps
link. All examples use only supported public APIs.

## Available Guides

1. [In-Memory Sessions](in_memory_sessions.md) — run sessions in a single process
   with `Host` and `Store`.
2. [Durable Sessions with SQLite](durable_sessions.md) — survive process restarts
   through `ProviderStore` and the optional ask-state-providers SQLite adapter.
3. [Subscriptions and Replay](subscriptions_and_replay.md) — stream a session's
   events live and resume from a sequence cursor.
4. [Tool Lifecycle Sink](tool_lifecycle.md) — record ask-runtime tool lifecycle
   through `Host#sink`.
5. [Export and Import](export_import.md) — move session history between stores
   safely.

## Assumptions

Every guide assumes Ruby 3.2+ and `require "ask-session"` in your application.
The durable guide additionally installs the optional
[ask-state-providers](https://github.com/ask-rb/ask-state-providers) gem in your
application — ask-session itself ships with zero runtime dependencies.
