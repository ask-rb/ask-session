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
    #
    # Concurrency: every public operation runs under an in-process mutex and,
    # when the adapter exposes the provider lock API (acquire_lock /
    # release_lock), under a cross-process store lock so read-modify-write
    # sequences (index updates, optimistic event appends) stay atomic across
    # processes and adapter connections. Adapters without lock methods fall
    # back to the in-process mutex alone. Stale expected_sequence writers
    # still fail with ConcurrencyError — locks serialize, they do not merge.
    class ProviderStore
      RECORD_PREFIX = "ask.session:record:"
      EVENTS_PREFIX = "ask.session:events:"
      INDEX_KEY = "ask.session:index"
      STORE_LOCK_KEY = "ask.session:lock"
      SYMBOL_TAG = "$ask_sym"
      LOCK_TTL = 10
      LOCK_TIMEOUT = 5
      LOCK_RETRY_MIN_DELAY = 0.001
      LOCK_RETRY_MAX_DELAY = 0.05

      def initialize(adapter:, lock_ttl: LOCK_TTL, lock_timeout: LOCK_TIMEOUT)
        unless adapter.respond_to?(:get) && adapter.respond_to?(:set) && adapter.respond_to?(:delete)
          raise ArgumentError, "adapter must respond to get, set, and delete"
        end

        @adapter = adapter
        @lock_ttl = lock_ttl
        @lock_timeout = lock_timeout
        @lockable = adapter.respond_to?(:acquire_lock) && adapter.respond_to?(:release_lock)
        @mutex = Mutex.new
      end

      def create(id: nil, status: :active, metadata: {}, created_at: nil)
        record = Record.create(id: id, status: status, metadata: metadata, created_at: created_at)
        with_store_lock do
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
        with_store_lock { read_record(id) }
      end

      def load!(id)
        load(id) || raise(NotFoundError, "Session not found: #{id}")
      end

      def list
        with_store_lock { read_index.filter_map { |id| read_record(id) } }
      end

      def append_event(event, expected_sequence:)
        with_store_lock do
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
        with_store_lock do
          raise NotFoundError, "Session not found: #{session_id}" unless exists?(session_id)

          read_events(session_id).select { |e| e.seq > after_seq }.freeze
        end
      end

      def current_sequence(session_id)
        with_store_lock do
          raise NotFoundError, "Session not found: #{session_id}" unless exists?(session_id)

          read_events(session_id).size
        end
      end

      def events(session_id)
        with_store_lock do
          raise NotFoundError, "Session not found: #{session_id}" unless exists?(session_id)

          read_events(session_id).dup.freeze
        end
      end

      def export(session_id = nil)
        with_store_lock do
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

        with_store_lock do
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

      # Serialize this process's operations, then take the adapter's
      # cross-process store lock when the provider exposes one. Adapters
      # without lock APIs fall back to the in-process mutex alone.
      def with_store_lock
        @mutex.synchronize do
          lock = acquire_store_lock if @lockable
          begin
            yield
          ensure
            release_store_lock(lock) if lock
          end
        end
      end

      # Spin (bounded) until the provider lock is acquired. The lock is
      # TTL-bounded by the adapter, so a crashed holder cannot wedge the
      # store forever; exhausting the wait budget surfaces as
      # ConcurrencyError rather than silently dropping mutual exclusion.
      #
      # Transient adapter errors during acquisition (e.g. a check-then-insert
      # race between connections on the lock row) are retried within the
      # same budget — losing the race means the lock is held elsewhere.
      def acquire_store_lock
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @lock_timeout
        delay = LOCK_RETRY_MIN_DELAY
        last_error = nil
        loop do
          begin
            lock = @adapter.acquire_lock(STORE_LOCK_KEY, ttl: @lock_ttl)
            return lock if lock
          rescue StandardError => e
            last_error = e
          end

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            message = "Timed out after #{@lock_timeout}s acquiring store lock"
            message = "#{message} (last error: #{last_error.message})" if last_error
            raise ConcurrencyError, message
          end

          sleep(delay)
          delay = [delay * 2, LOCK_RETRY_MAX_DELAY].min
        end
      end

      # A failed release must never mask the operation's own outcome —
      # the adapter's TTL reclaims the lock if the token delete failed.
      def release_store_lock(lock)
        @adapter.release_lock(STORE_LOCK_KEY, lock)
      rescue StandardError
        nil
      end

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
