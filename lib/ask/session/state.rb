# frozen_string_literal: true

module Ask
  module Session
    module State
      def self.reduce(session_id, events)
        record = nil

        events.each do |event|
          record = apply_event(record, event)
        end

        (record || Record.create(id: session_id, created_at: Time.now.utc)).freeze
      end

      def self.apply_event(record, event)
        case event.type
        when "session.created"
          Record.new(
            id: event.session_id,
            status: event.payload.fetch(:status, :active),
            metadata: event.payload.fetch(:metadata, {}),
            created_at: event.created_at,
            updated_at: event.created_at,
            version: event.seq
          )
        when "session.status_changed"
          raise "No session to update" unless record

          record.with_updates(
            status: event.payload.fetch(:status, record.status),
            version: event.seq,
            updated_at: event.created_at
          )
        when "message.added"
          raise "No session to update" unless record

          record.with_updates(
            version: event.seq,
            updated_at: event.created_at
          )
        when "tool.completed"
          raise "No session to update" unless record

          record.with_updates(
            version: event.seq,
            updated_at: event.created_at
          )
        else
          # Unknown event types remain in history without crashing
          record
        end
      end
      private_class_method :apply_event
    end
  end
end
