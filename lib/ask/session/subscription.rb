# frozen_string_literal: true

module Ask
  module Session
    class Subscription
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
        @queue.push(:closed)
      end

      def wait(timeout: nil)
        return nil if closed?

        if timeout
          deadline = Time.now.utc + timeout
          loop do
            return nil if closed?
            begin
              val = @queue.pop(true)
              return val unless val == :closed
            rescue ThreadError
            end
            remaining = deadline - Time.now.utc
            return nil if remaining <= 0
            sleep [remaining, 0.01].min
          end
        else
          val = @queue.pop
          val == :closed ? nil : val
        end
      end

      def each
        while (event = wait(timeout: 0.1))
          yield event
        end
      end

      def enqueue(event)
        @queue.push(event) unless closed?
      end
    end
  end
end
