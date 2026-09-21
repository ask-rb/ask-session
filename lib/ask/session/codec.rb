# frozen_string_literal: true

module Ask
  module Session
    module Codec
      RECORD_KEYS = %i[id status metadata created_at updated_at version].freeze
      EVENT_KEYS = %i[session_id seq type payload trace_id causation_id created_at].freeze

      def self.dump_record(record)
        JSON.generate(record.to_h)
      end

      def self.load_record(json)
        h = parse_json(json)
        validate_keys!(h, RECORD_KEYS, "Record")
        Record.from_h(symbolize(h))
      rescue JSON::ParserError => e
        raise SerializationError, "Invalid JSON for Record: #{e.message}"
      end

      def self.dump_event(event)
        JSON.generate(event.to_h)
      end

      def self.load_event(json)
        h = parse_json(json)
        validate_keys!(h, EVENT_KEYS, "Event")
        Event.from_h(symbolize(h))
      rescue JSON::ParserError => e
        raise SerializationError, "Invalid JSON for Event: #{e.message}"
      end

      def self.parse_json(json)
        raise SerializationError, "Input must be a String" unless json.is_a?(String)
        JSON.parse(json)
      end
      private_class_method :parse_json

      def self.validate_keys!(h, required, label)
        required.each do |key|
          ks = key.to_s
          next if h.key?(ks) && !h[ks].nil?

          raise SerializationError, "Missing required field '#{ks}' in #{label}"
        end
      end
      private_class_method :validate_keys!

      def self.symbolize(h)
        h.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
      end
      private_class_method :symbolize
    end
  end
end
