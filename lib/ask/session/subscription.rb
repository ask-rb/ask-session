# frozen_string_literal: true

require "timeout"

module Ask
  module Session
    class Subscription
      SENTINEL = Object.new

      attr_reader :id, :session_id

      def initialize(id:, session_id:)
        @id = id
        @session_id = session_id
        @queue = Queue.new
        @closed = false
        @mutex = Mutex.new
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      def close
        @mutex.synchronize { @closed = true }
        @queue.push(SENTINEL)
      end

      def next(timeout: nil)
        return nil if closed?

        if timeout
          val = Timeout.timeout(timeout) { @queue.pop }
          val.equal?(SENTINEL) ? nil : val
        else
          val = @queue.pop
          val.equal?(SENTINEL) ? nil : val
        end
      rescue Timeout::Error
        nil
      end

      alias_method :wait, :next

      def each
        while (event = self.next(timeout: 0.1))
          yield event
        end
      end

      def enqueue(event)
        @queue.push(event) unless closed?
      end
    end
  end
end
