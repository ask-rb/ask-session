# Ask::Session

Event-sourced session state for the [ask-rb](https://github.com/ask-rb) ecosystem.

## Overview

Ask::Session provides the foundational value objects and stores for event-sourced
session management in ask-rb: immutable `Record` and `Event` envelopes, an
in-memory `Store` with concurrency guardrails, a durable `ProviderStore` for
restart-safe sessions, a replayable `Host` with subscriptions, a
`State` reducer, and a `Sink` that records ask-runtime tool lifecycle through
`Host#sink`. It ships with zero runtime dependencies — durability through
[ask-state-providers](https://github.com/ask-rb/ask-state-providers) is an
optional integration.

Task guides live in [docs/](https://github.com/ask-rb/ask-session/blob/master/docs/index.md).

## Installation

Requires Ruby 3.2+.

```ruby
gem "ask-session"
```

## Quick start

In-memory, single process:

```ruby
require "ask-session"

host = Ask::Session::Host.new

host.create(id: "s1", metadata: { user: "alice" })
host.send_message("s1", content: "hello")
host.session("s1").version # => 2
host.close("s1", reason: "done")
```

Invalid transitions (sending to a closed session, closing twice) raise
`Ask::Session::InvalidTransitionError`.

## Guides

- [Guides index](https://github.com/ask-rb/ask-session/blob/master/docs/index.md)
- [In-memory sessions](https://github.com/ask-rb/ask-session/blob/master/docs/in_memory_sessions.md)
- [Durable sessions with SQLite (optional ask-state-providers)](https://github.com/ask-rb/ask-session/blob/master/docs/durable_sessions.md)
- [Subscriptions and replay](https://github.com/ask-rb/ask-session/blob/master/docs/subscriptions_and_replay.md)
- [Tool lifecycle through Host#sink](https://github.com/ask-rb/ask-session/blob/master/docs/tool_lifecycle.md)
- [Export and import](https://github.com/ask-rb/ask-session/blob/master/docs/export_import.md)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Create a Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.
