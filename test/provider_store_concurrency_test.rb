# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

CONCURRENCY_PROVIDER_AVAILABLE =
  if defined?(PROVIDER_AVAILABLE)
    PROVIDER_AVAILABLE
  else
    begin
      require "ask-state-providers"
      true
    rescue LoadError
      begin
        require "ask/state"
        require "ask/state/providers/sqlite"
        true
      rescue LoadError
        false
      end
    end
  end

# Minimal get/set/delete-only adapter — no provider lock API. Exercises the
# in-process mutex fallback path of ProviderStore.
class PlainKVAdapter
  def initialize
    @data = {}
    @mutex = Mutex.new
  end

  def get(key)
    @mutex.synchronize { @data[key] }
  end

  def set(key, value, **)
    @mutex.synchronize { @data[key] = value }
  end

  def delete(key)
    @mutex.synchronize { @data.delete(key) }
  end
end

# Lock API present but permanently unavailable — every acquire returns nil.
class NeverYieldingLockAdapter < PlainKVAdapter
  def acquire_lock(key, ttl: 10)
    nil
  end

  def release_lock(key, lock)
    false
  end
end

# Delegates to a real provider adapter while counting lock acquire/release.
class LockCountingAdapter
  attr_reader :acquired, :released

  def initialize(inner)
    @inner = inner
    @acquired = 0
    @released = 0
    @counter_mutex = Mutex.new
  end

  def get(key)
    @inner.get(key)
  end

  def set(key, value, **opts)
    @inner.set(key, value, **opts)
  end

  def delete(key)
    @inner.delete(key)
  end

  def acquire_lock(key, ttl: 10)
    lock = @inner.acquire_lock(key, ttl: ttl)
    @counter_mutex.synchronize { @acquired += 1 } if lock
    lock
  end

  def release_lock(key, lock)
    @counter_mutex.synchronize { @released += 1 }
    @inner.release_lock(key, lock)
  end
end

class ProviderStoreConcurrencyTest < Minitest::Test
  THREADS = 4
  APPENDS_PER_THREAD = 5

  def setup
    skip "ask-state-providers is not available" unless CONCURRENCY_PROVIDER_AVAILABLE
    skip "Ask::State::Providers::SQLite not defined" unless defined?(Ask::State::Providers::SQLite)

    @dir = Dir.mktmpdir("ask-session-concurrency")
    @db_path = File.join(@dir, "sessions.db")
    @adapters = []
  end

  def teardown
    @adapters.each do |adapter|
      adapter.close if adapter.respond_to?(:close)
    rescue StandardError
      nil
    end
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_concurrent_appends_across_connections_preserve_sequence
    stores = Array.new(THREADS) { build_sqlite_store }
    writer = stores.first
    writer.create(id: "s1")

    errors = run_threads(stores) do |store, i|
      APPENDS_PER_THREAD.times do |j|
        optimistic_append(store, "s1", "msg.#{i}.#{j}")
      end
    end
    assert_empty errors, "concurrent appends raised: #{errors.map(&:inspect).join(", ")}"

    expected = (1..(THREADS * APPENDS_PER_THREAD)).to_a
    assert_equal expected, writer.events("s1").map(&:seq),
      "event sequence must be contiguous with no gaps or duplicates"
    assert_equal THREADS * APPENDS_PER_THREAD, writer.current_sequence("s1")

    total = writer.export("s1")[:events].size
    assert_equal THREADS * APPENDS_PER_THREAD, total
  end

  def test_concurrent_create_same_id_single_winner
    stores = Array.new(THREADS) { build_sqlite_store }

    outcomes = Queue.new
    threads = stores.map do |store|
      Thread.new do
        begin
          store.create(id: "dup")
          outcomes << :created
        rescue Ask::Session::DuplicateSessionError
          outcomes << :duplicate
        rescue StandardError => e
          outcomes << e
        end
      end
    end
    threads.each(&:join)

    results = Array.new(outcomes.size) { outcomes.pop }
    unexpected = results.reject { |r| r == :created || r == :duplicate }
    assert_empty unexpected, "unexpected errors: #{unexpected.map(&:inspect).join(", ")}"
    assert_equal 1, results.count(:created), "exactly one concurrent create must win"
    assert_equal THREADS - 1, results.count(:duplicate)

    index = stores.first.list.map(&:id)
    assert_equal ["dup"], index, "index must contain the session exactly once"
  end

  def test_stale_expected_sequence_across_connections_raises_concurrency_error
    store_a = build_sqlite_store
    store_b = build_sqlite_store
    store_a.create(id: "s1")

    store_a.append_event(build_seq_event("s1", 1), expected_sequence: 0)

    assert_equal 1, store_a.current_sequence("s1")
    assert_equal 1, store_b.current_sequence("s1")

    store_a.append_event(build_seq_event("s1", 2), expected_sequence: 1)

    assert_raises(Ask::Session::ConcurrencyError) do
      store_b.append_event(build_seq_event("s1", 2), expected_sequence: 1)
    end

    assert_equal [1, 2], store_b.events("s1").map(&:seq),
      "stale write must be rejected without corrupting stored events"
  end

  def test_provider_lock_api_is_used_and_balanced
    inner = Ask::State::Providers::SQLite.new(path: @db_path)
    @adapters << inner
    adapter = LockCountingAdapter.new(inner)
    store = Ask::Session::ProviderStore.new(adapter: adapter)

    store.create(id: "s1")
    store.append_event(build_seq_event("s1", 1), expected_sequence: 0)
    store.events("s1")
    store.current_sequence("s1")
    store.list

    assert_operator adapter.acquired, :>, 0, "store must acquire the provider lock"
    assert_equal adapter.acquired, adapter.released, "every acquired lock must be released"
  end

  def test_provider_lock_released_when_operation_raises
    inner = Ask::State::Providers::SQLite.new(path: @db_path)
    @adapters << inner
    adapter = LockCountingAdapter.new(inner)
    store = Ask::Session::ProviderStore.new(adapter: adapter)

    assert_raises(Ask::Session::NotFoundError) { store.events("missing") }

    assert_equal adapter.acquired, adapter.released,
      "lock must be released even when the operation raises"

    store.create(id: "s1")
    assert_equal "s1", store.load!("s1").id,
      "store must remain usable after a failed operation"
  end

  def test_fallback_without_lock_api_preserves_sequence_under_threads
    store = Ask::Session::ProviderStore.new(adapter: PlainKVAdapter.new)
    store.create(id: "s1")

    errors = run_threads(Array.new(THREADS) { store }) do |s, i|
      APPENDS_PER_THREAD.times do |j|
        optimistic_append(s, "s1", "msg.#{i}.#{j}")
      end
    end
    assert_empty errors, "mutex-fallback appends raised: #{errors.map(&:inspect).join(", ")}"

    expected = (1..(THREADS * APPENDS_PER_THREAD)).to_a
    assert_equal expected, store.events("s1").map(&:seq)
  end

  def test_lock_timeout_raises_concurrency_error
    store = Ask::Session::ProviderStore.new(
      adapter: NeverYieldingLockAdapter.new,
      lock_timeout: 0.05
    )

    error = assert_raises(Ask::Session::ConcurrencyError) { store.create(id: "s1") }
    assert_match(/store lock/, error.message)
  end

  private

  def build_sqlite_store
    adapter = Ask::State::Providers::SQLite.new(path: @db_path)
    @adapters << adapter
    Ask::Session::ProviderStore.new(adapter: adapter)
  end

  def build_seq_event(session_id, seq)
    Ask::Session::Event.create(
      session_id: session_id,
      seq: seq,
      type: "message.added",
      payload: { content: "event-#{seq}" }
    )
  end

  # Optimistic read-append with retry: between current_sequence and
  # append_event another writer may win the lock, so a stale expectation
  # fails with ConcurrencyError and is retried against fresh state.
  def optimistic_append(store, session_id, type, max_attempts: 500)
    attempts = 0
    begin
      attempts += 1
      seq = store.current_sequence(session_id)
      event = Ask::Session::Event.create(
        session_id: session_id,
        seq: seq + 1,
        type: type,
        payload: {}
      )
      store.append_event(event, expected_sequence: seq)
    rescue Ask::Session::ConcurrencyError
      raise if attempts >= max_attempts
      retry
    end
  end

  def run_threads(stores)
    errors = Queue.new
    threads = stores.each_with_index.map do |store, i|
      Thread.new do
        yield store, i
      rescue StandardError => e
        errors << e
      end
    end
    threads.each(&:join)
    Array.new(errors.size) { errors.pop }
  end
end

class ProviderStoreHostConcurrencyTest < Minitest::Test
  HOSTS = 4
  MESSAGES_PER_HOST = 5

  def setup
    skip "ask-state-providers is not available" unless CONCURRENCY_PROVIDER_AVAILABLE
    skip "Ask::State::Providers::SQLite not defined" unless defined?(Ask::State::Providers::SQLite)

    @dir = Dir.mktmpdir("ask-session-host-concurrency")
    @db_path = File.join(@dir, "sessions.db")
    @adapters = []
  end

  def teardown
    @adapters.each do |adapter|
      adapter.close if adapter.respond_to?(:close)
    rescue StandardError
      nil
    end
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_hosts_on_separate_connections_keep_sequence_intact
    hosts = Array.new(HOSTS) do
      adapter = Ask::State::Providers::SQLite.new(path: @db_path)
      @adapters << adapter
      store = Ask::Session::ProviderStore.new(adapter: adapter)
      Ask::Session::Host.new(store: store)
    end

    hosts.first.create(id: "s1")

    errors = Queue.new
    threads = hosts.each_with_index.map do |host, i|
      Thread.new do
        MESSAGES_PER_HOST.times do |j|
          retry_on_conflict { host.send_message("s1", content: "h#{i}-m#{j}") }
        end
      rescue StandardError => e
        errors << e
      end
    end
    threads.each(&:join)

    raised = Array.new(errors.size) { errors.pop }
    assert_empty raised, "host appends raised: #{raised.map(&:inspect).join(", ")}"

    events = hosts.first.events("s1")
    expected = (1..(HOSTS * MESSAGES_PER_HOST + 1)).to_a # +1 for session.created
    assert_equal expected, events.map(&:seq)
    assert_equal expected.last, hosts.last.session("s1").version
  end

  private

  # Host#send_message reads the sequence and appends under its own mutex;
  # across hosts that optimistic window can lose the race, so retry against
  # fresh state. Partial writes never occur — append_event fails before
  # mutating on a stale expectation.
  def retry_on_conflict(max_attempts: 500)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue Ask::Session::ConcurrencyError
      raise if attempts >= max_attempts
      retry
    end
  end
end
