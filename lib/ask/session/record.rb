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

      def initialize(**)
        super
        self.metadata = deep_freeze(metadata) unless metadata.frozen?
        freeze
      end

      def with_updates(**attrs)
        self.class.new(**to_h.merge(attrs).merge(updated_at: attrs[:updated_at] || Time.now.utc)).freeze
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
