# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ask-session"

require "minitest/autorun"

module TestHelpers
  def build_record(**overrides)
    defaults = {
      id: "sess_001",
      status: :active,
      metadata: {},
      created_at: Time.utc(2026, 1, 1),
      updated_at: Time.utc(2026, 1, 1),
      version: 0
    }
    Ask::Session::Record.new(**defaults.merge(overrides))
  end

  def build_event(**overrides)
    defaults = {
      session_id: "sess_001",
      seq: 1,
      type: "session.created",
      payload: {},
      trace_id: "trace_001",
      causation_id: nil,
      created_at: Time.utc(2026, 1, 1)
    }
    Ask::Session::Event.new(**defaults.merge(overrides))
  end
end
