# frozen_string_literal: true

module Ask
  module Session
    class Store
      def initialize
        @sessions = {}
        @events = {}
        @mutex = Mutex.new
      end

      def create(id: nil, status: :active, metadata: {}, created_at: nil)
        record = Record.create(id: id, status: status, metadata: metadata, created_at: created_at)
        @mutex.synchronize do
          if @sessions.key?(record.id)
            raise DuplicateSessionError, "Session already exists: #{record.id}"
          end
          @sessions[record.id] = record
          @events[record.id] = []
        end
        record
      end

      def load(id)
        @mutex.synchronize { @sessions[id] }
      end

      def load!(id)
        load(id) || raise(NotFoundError, "Session not found: #{id}")
      end

      def list
        @mutex.synchronize { @sessions.values.dup }
      end

      def append_event(event, expected_sequence:)
        @mutex.synchronize do
          session_events = @events[event.session_id]
          raise NotFoundError, "Session not found: #{event.session_id}" unless session_events

          current_seq = session_events.size
          unless current_seq == expected_sequence
            raise ConcurrencyError,
              "Expected sequence #{expected_sequence} but got #{current_seq} for session #{event.session_id}"
          end

          unless event.seq == current_seq + 1
            raise ConcurrencyError,
              "Event seq #{event.seq} does not match expected next sequence #{current_seq + 1} for session #{event.session_id}"
          end

          session_events << event
        end
        event
      end

      def events_after(session_id, after_seq:)
        @mutex.synchronize do
          session_events = @events[session_id]
          raise NotFoundError, "Session not found: #{session_id}" unless session_events

          session_events.select { |e| e.seq > after_seq }
        end
      end

      def current_sequence(session_id)
        @mutex.synchronize do
          session_events = @events[session_id]
          raise NotFoundError, "Session not found: #{session_id}" unless session_events

          session_events.size
        end
      end
    end
  end
end
