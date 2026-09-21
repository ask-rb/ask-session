# frozen_string_literal: true

module Ask
  module Session
    Event = Struct.new(:session_id, :seq, :type, :payload, :trace_id, :causation_id, :created_at, keyword_init: true) do
      def self.create(session_id:, seq:, type:, payload: {}, trace_id: nil, causation_id: nil, created_at: nil)
        new(
          session_id: session_id,
          seq: seq,
          type: type,
          payload: payload,
          trace_id: trace_id || "trace_#{SecureRandom.hex(8)}",
          causation_id: causation_id,
          created_at: created_at || Time.now.utc
        )
      end
    end
  end
end
