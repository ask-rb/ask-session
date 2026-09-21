# frozen_string_literal: true

module Ask
  module Session
    Record = Struct.new(:id, :status, :metadata, :created_at, :updated_at, :version, keyword_init: true) do
      def self.create(id: nil, status: :active, metadata: {}, created_at: nil, updated_at: nil)
        now = created_at || Time.now.utc
        new(
          id: id || "sess_#{SecureRandom.hex(8)}",
          status: status,
          metadata: metadata,
          created_at: now,
          updated_at: updated_at || now,
          version: 0
        ).freeze
      end

      def to_h
        {
          id: id,
          status: status,
          metadata: metadata,
          created_at: created_at&.utc&.iso8601,
          updated_at: updated_at&.utc&.iso8601,
          version: version
        }
      end

      def self.from_h(h)
        new(
          id: h[:id] || h["id"],
          status: (h[:status] || h["status"])&.to_sym,
          metadata: deep_symbolize(h[:metadata] || h["metadata"]),
          created_at: parse_time(h[:created_at] || h["created_at"]),
          updated_at: parse_time(h[:updated_at] || h["updated_at"]),
          version: h[:version] || h["version"]
        )
      end

      def self.deep_symbolize(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize(v) }
        when Array
          obj.map { |v| deep_symbolize(v) }
        else
          obj
        end
      end
      private_class_method :deep_symbolize

      def self.parse_time(value)
        case value
        when Time then value
        when String then Time.parse(value).utc
        when nil then nil
        else
          raise SerializationError, "Invalid time value: #{value.inspect}"
        end
      end
      private_class_method :parse_time

      def initialize(**)
        super
        self.metadata = deep_freeze(metadata) unless metadata.frozen?
        freeze
      end

      def with_updates(**attrs)
        merged = {
          id: id,
          status: status,
          metadata: metadata,
          created_at: created_at,
          updated_at: attrs[:updated_at] || Time.now.utc,
          version: version
        }.merge(attrs)
        self.class.new(**merged).freeze
      end

      private

      def deep_freeze(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k] = deep_freeze(v) }.freeze
        when Array
          obj.map { |v| deep_freeze(v) }.freeze
        else
          obj
        end
      end
    end
  end
end
