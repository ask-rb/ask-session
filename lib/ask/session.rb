# frozen_string_literal: true

require "securerandom"

require_relative "session/version"
require_relative "session/record"
require_relative "session/event"
require_relative "session/store"
require_relative "session/state"

module Ask
  module Session
    class Error < StandardError; end
    class ConcurrencyError < Error; end
    class NotFoundError < Error; end
    class DuplicateSessionError < Error; end
  end
end
