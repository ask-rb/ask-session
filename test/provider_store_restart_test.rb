# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

PROVIDER_AVAILABLE =
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

class ProviderStoreRestartTest < Minitest::Test
  def setup
    unless PROVIDER_AVAILABLE && defined?(Ask::State::Providers::SQLite)
      skip "ask-state-providers is not available"
    end

    @dir = Dir.mktmpdir("ask-session-restart")
    @db_path = File.join(@dir, "sessions.db")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_session_events_and_state_survive_restart
    adapter1 = Ask::State::Providers::SQLite.new(path: @db_path)
    store1 = Ask::Session::ProviderStore.new(adapter: adapter1)
    host1 = Ask::Session::Host.new(store: store1)

    host1.create(id: "s_restart", metadata: { user: "alice" })
    host1.send_message("s_restart", content: "hello")
    host1.append("s_restart", type: "custom.phase.started",
      payload: { phase: :discovery, role: :user })
    host1.close("s_restart", reason: "done")
    adapter1.close

    adapter2 = Ask::State::Providers::SQLite.new(path: @db_path)
    store2 = Ask::Session::ProviderStore.new(adapter: adapter2)
    host2 = Ask::Session::Host.new(store: store2)

    record = host2.session("s_restart")
    assert_equal "s_restart", record.id
    assert_equal :closed, record.status
    assert_equal({ user: "alice" }, record.metadata)
    assert_equal 4, record.version
    assert_instance_of Time, record.updated_at

    events = host2.events("s_restart")
    assert_equal 4, events.size
    assert_equal [1, 2, 3, 4], events.map(&:seq)
    assert_equal ["session.created", "message.added", "custom.phase.started", "session.ended"],
      events.map(&:type)
    assert_equal({ content: "hello" }, events[1].payload)
    assert_equal({ phase: :discovery, role: :user }, events[2].payload)
    assert_equal :closed, events[3].payload[:status]
    assert_equal "done", events[3].payload[:reason]

    assert_equal 4, store2.current_sequence("s_restart")
    after = store2.events_after("s_restart", after_seq: 2)
    assert_equal 2, after.size
    assert_equal [3, 4], after.map(&:seq)

    loaded = store2.load!("s_restart")
    assert_equal "s_restart", loaded.id
    assert_equal :active, loaded.status
    assert_equal({ user: "alice" }, loaded.metadata)

    assert_equal ["s_restart"], host2.list.map(&:id)
    assert_equal :closed, host2.list.first.status

    assert_raises(Ask::Session::DuplicateSessionError) do
      host2.create(id: "s_restart")
    end
    assert_raises(Ask::Session::InvalidTransitionError) do
      host2.send_message("s_restart", content: "nope")
    end

    adapter2.close
  end
end
