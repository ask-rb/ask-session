# frozen_string_literal: true

module Ask
  module Session
    # Durable Store implementation backed by a generic ask-state-providers
    # adapter (get/set/delete). Each session's record and event list persist
    # under namespaced keys so sessions survive process restarts.
    #
    # Serialization is JSON with symbol-safe encoding: symbol values (status,
    # payload symbols) round-trip exactly, and Record/Event from_h restore
    # keys, timestamps, and nested structures.
    class ProviderStore
      RECORD_PREFIX = "ask.session:record:"
      EVENTS_PREFIX = "ask.session:events:"
      INDEX_KEY = "ask.session:index"
      SYMBOL_TAG = "$ask_sym"

      def initialize(adapter:)
        unless adapter.respond_to?(:get) && adapter.respond_to?(:set) && adapter.respond_to?(:delete)
          raise ArgumentError, "adapter must respond to get, set, and delete"
        end

        @adapter = adapter
        @mutex = Mutex.new
      end

      def create(id: nil, status: :active, metadata: {}, created_at: nil)
        record = Record.create(id: id, status: status, metadata: metadata, created_at: created_at)
        @mutex.synchronize do
          if @adapter.get(record_key(record.id))
            raise DuplicateSessionError, "Session already exists: #{record.id}"
          end

          @adapter.set(record_key(record.id), dump(record.to_h))
          @adapter.set(events_key(record.id), dump([]))
          ids = read_index
          ids << record.id
          @adapter.set(INDEX_KEY, dump(ids))
        end
        record
      end

      def load(id)
        @mutex.synchronize { read_record(id) }
      end

      def load!(id)
        load(id) || raise(NotFoundError, "Session not found: #{id}")
      end

      def list
        @mutex.synchronize { read_index.filter_map { |id| read_record(id) } }
      end

      def append_event(event, expected_sequence:)
        @mutex.synchronize do
          unless exists?(event.session_id)
            raise NotFoundError, "Session not found: #{event.session_id}"
          end

          session_events = read_events(event.session_id)
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
          write_events(event.session_id, session_events)
        end
        event
      end

      def state(session_id)
        State.reduce(session_id, events(session_id))
      end

      def events_after(session_id, after_seq:)
        @mutex.synchronize do
          raise NotFoundError, "Session not found: #{session_id}" unless exists?(session_id)

          read_events(session_id).select { |e| e.seq > after_seq }.freeze
        end
      end

      def current_sequence(session_id)
        @mutex.synchronize do
          raise NotFoundError, "Session not found: #{session_id}" unless exists?(session_id)

          read_events(session_id).size
        end
      end

      def events(session_id)
        @mutex.synchronize do
          raise NotFoundError, "Session not found: #{session_id}" unless exists?(session_id)

          read_events(session_id).dup.freeze
        end
      end

      def export(session_id = nil)
        @mutex.synchronize do
          if session_id
            record = read_record(session_id)
            raise NotFoundError, "Session not found: #{session_id}" unless record

            {
              sessions: [record.to_h],
              events: read_events(session_id).map(&:to_h)
            }
          else
            records = read_index.filter_map { |id| read_record(id) }
            {
              sessions: records.map(&:to_h),
              events: records.flat_map { |r| read_events(r.id).map(&:to_h) }
            }
          end
        end
      end

      def import(data)
        sessions = data[:sessions] || data["sessions"] || []
        events = data[:events] || data["events"] || []

        @mutex.synchronize do
          pending_sessions = {}
          pending_events = {}
          existing_events = {}

          sessions.each do |s|
            id = s[:id] || s["id"]
            raise SerializationError, "Session record missing id" unless id && !id.to_s.empty?
            raise DuplicateSessionError, "Session already exists: #{id}" if exists?(id)
            raise DuplicateSessionError, "Duplicate session in import data: #{id}" if pending_sessions.key?(id)

            record = Record.from_h(s)
            pending_sessions[record.id] = record
            pending_events[record.id] = []
          end

          events.each do |e|
            session_id = e[:session_id] || e["session_id"]
            session_events =
              if pending_events.key?(session_id)
                pending_events[session_id]
              elsif exists?(session_id)
                existing_events[session_id] ||= read_events(session_id)
              else
                raise NotFoundError, "Session not found: #{session_id}"
              end

            event = Event.from_h(e)
            expected_seq = session_events.size
            unless event.seq == expected_seq + 1
              raise ConcurrencyError,
                "Expected sequence #{expected_seq + 1} but got #{event.seq} for session #{session_id}"
            end

            session_events << event
          end

          pending_sessions.each do |id, record|
            @adapter.set(record_key(id), dump(record.to_h))
            @adapter.set(events_key(id), dump(pending_events[id].map(&:to_h)))
          end
          existing_events.each { |id, session_events| write_events(id, session_events) }

          unless pending_sessions.empty?
            ids = read_index
            pending_sessions.each_key { |id| ids << id }
            @adapter.set(INDEX_KEY, dump(ids))
          end
        end
      end

      private

      def exists?(id)
        !@adapter.get(record_key(id)).nil?
      end

      def read_record(id)
        raw = @adapter.get(record_key(id))
        return nil unless raw

        Record.from_h(decode(JSON.parse(raw)))
      end

      def read_events(id)
        raw = @adapter.get(events_key(id))
        return [] unless raw

        decode(JSON.parse(raw)).map { |h| Event.from_h(h) }
      end

      def write_events(id, session_events)
        @adapter.set(events_key(id), dump(session_events.map(&:to_h)))
      end

      def read_index
        raw = @adapter.get(INDEX_KEY)
        raw ? decode(JSON.parse(raw)) : []
      end

      def record_key(id)
        "#{RECORD_PREFIX}#{id}"
      end

      def events_key(id)
        "#{EVENTS_PREFIX}#{id}"
      end

      def dump(obj)
        JSON.generate(encode(obj))
      end

      def encode(obj)
        case obj
        when Symbol then { SYMBOL_TAG => obj.to_s }
        when Hash
          obj.each_with_object({}) { |(k, v), acc| acc[k] = encode(v) }
        when Array then obj.map { |v| encode(v) }
        else obj
        end
      end

      def decode(obj)
        case obj
        when Hash
          if obj.size == 1 && obj.key?(SYMBOL_TAG) && obj[SYMBOL_TAG].is_a?(String)
            obj[SYMBOL_TAG].to_sym
          else
            obj.each_with_object({}) { |(k, v), acc| acc[k] = decode(v) }
          end
        when Array then obj.map { |v| decode(v) }
        else obj
        end
      end
    end
  end
end
