# frozen_string_literal: true

require "json"
require "time"
require "securerandom"

require_relative "session/version"
require_relative "session/record"
require_relative "session/event"
require_relative "session/store"
require_relative "session/state"
require_relative "session/codec"

module Ask
  module Session
    class Error < StandardError; end
    class ConcurrencyError < Error; end
    class NotFoundError < Error; end
    class DuplicateSessionError < Error; end
    class SerializationError < Error; end
  end
end
