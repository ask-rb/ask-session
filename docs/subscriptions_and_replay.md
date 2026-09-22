# Subscriptions and Replay

This guide covers subscribing to a session's events with
`Host#subscribe`, replaying history into the subscriber, and consuming live
events with `Ask::Session::Subscription`.

Use this when another thread or component needs to observe a session as it
happens: streaming a transcript to a UI, feeding a live consumer, or resuming
from a known sequence cursor without re-reading everything.

## Prerequisites and Setup

- Everything from [In-Memory Sessions](in_memory_sessions.md)
- An existing session — `subscribe` on a missing id raises
  `Ask::Session::NotFoundError`

Subscriptions work over any store behind the `Host`, in-memory or
`ProviderStore`.

## Example

```ruby
require "ask-session"

host = Ask::Session::Host.new
host.create(id: "s1")
host.send_message("s1", content: "one")

# Subscribe: history is replayed into the queue first, then live events follow.
sub = host.subscribe("s1")
sub.next # => session.created event (replay)
sub.next # => message.added event   (replay)

host.send_message("s1", content: "two")
event = sub.next(timeout: 1.0) # => live message.added, or nil on timeout

# Resume from a cursor: only events with seq > after_seq are replayed,
# then live events continue.
host.send_message("s1", content: "three")
cursor = host.subscribe("s1", after_seq: 2)
cursor.next.type # => "message.added" (seq 3 only)

# Blocking iteration runs until the subscription is closed.
Thread.new { sub.each { |e| puts e.type } }
host.send_message("s1", content: "four")
sub.close
sub.closed? # => true
```

You can also pull history directly without subscribing:
`host.events("s1", after_seq: 2)` returns the frozen snapshot of events past a
sequence.

## Expected Behavior and Trade-offs

- **Replay then live.** `subscribe(session_id, after_seq:)` enqueues matching
  stored events at subscribe time (default `after_seq: 0`, i.e. all history),
  then receives every subsequent event published for that session — in `seq`
  order, since the host serializes appends.
- **Per-subscriber queue.** Each subscription has its own thread-safe queue;
  subscribers only see their own session. The host prunes closed subscriptions
  when publishing.
- **Timeout vs. close.** `next(timeout:)` (aliased `wait`) returns `nil` on
  timeout *and* after close — check `closed?` when you need to tell them apart.
  A blocked `next` wakes with `nil` when the subscription closes.
- **`each` blocks until close.** It yields across quiet periods and only stops
  on `close`; run it on a dedicated thread if the consumer should not block the
  caller.
- **Not durable.** Subscriptions live in process memory; after a restart, build
  a new subscription with an `after_seq` cursor (or read
  `host.events(id, after_seq:)`) to catch up. An undrained queue retains
  events, so drain or close subscribers you no longer need.

## Next Steps

[Tool Lifecycle Sink](tool_lifecycle.md) — record ask-runtime tool lifecycle
events into a session, and subscribe to watch them arrive.
