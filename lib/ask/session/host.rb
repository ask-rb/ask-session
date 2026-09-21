# frozen_string_literal: true

module Ask
  module Session
    class Host
      def initialize(store: Store.new)
        @store = store
        @subscriptions = {}
        @mutex = Mutex.new
        @sub_id_counter = 0
      end

      def create(id: nil, metadata: {}, status: :active, trace_id: nil)
        @mutex.synchronize do
          record = @store.create(id: id, status: status, metadata: metadata)
          event = Event.create(
            session_id: record.id,
            seq: 1,
            type: "session.created",
            payload: { session_id: record.id, metadata: metadata, status: status },
            trace_id: trace_id
          )
          @store.append_event(event, expected_sequence: 0)
          publish(event)
          State.reduce(record.id, @store.events(record.id))
        end
      end

      def session(id)
        State.reduce(id, @store.events(id))
      end

      def list
        @store.list.map { |record| State.reduce(record.id, @store.events(record.id)) }
      end

      def events(id, after_seq: 0)
        @store.events_after(id, after_seq: after_seq)
      end

      def send_message(session_id, content:, trace_id: nil, causation_id: nil)
        @mutex.synchronize do
          record = current_state(session_id)
          assert_open!(record)

          seq = @store.current_sequence(session_id) + 1
          event = Event.create(
            session_id: session_id,
            seq: seq,
            type: "message.added",
            payload: { content: content },
            trace_id: trace_id,
            causation_id: causation_id
          )
          @store.append_event(event, expected_sequence: seq - 1)
          publish(event)
          event
        end
      end

      def append(session_id, type:, payload: {}, trace_id: nil, causation_id: nil)
        @mutex.synchronize do
          record = current_state(session_id)
          assert_open!(record)

          seq = @store.current_sequence(session_id) + 1
          event = Event.create(
            session_id: session_id,
            seq: seq,
            type: type,
            payload: payload,
            trace_id: trace_id,
            causation_id: causation_id
          )
          @store.append_event(event, expected_sequence: seq - 1)
          publish(event)
          event
        end
      end

      def close(session_id, reason: nil)
        @mutex.synchronize do
          record = current_state(session_id)
          assert_open!(record)

          seq = @store.current_sequence(session_id) + 1
          event = Event.create(
            session_id: session_id,
            seq: seq,
            type: "session.ended",
            payload: { status: :closed, reason: reason }
          )
          @store.append_event(event, expected_sequence: seq - 1)
          publish(event)
          State.reduce(session_id, @store.events(session_id))
        end
      end

      def abort(session_id, reason: nil)
        @mutex.synchronize do
          record = current_state(session_id)
          assert_open!(record)

          seq = @store.current_sequence(session_id) + 1
          event = Event.create(
            session_id: session_id,
            seq: seq,
            type: "session.aborted",
            payload: { status: :aborted, reason: reason }
          )
          @store.append_event(event, expected_sequence: seq - 1)
          publish(event)
          State.reduce(session_id, @store.events(session_id))
        end
      end

      def subscribe(session_id, after_seq: 0)
        @mutex.synchronize do
          replay = @store.events_after(session_id, after_seq: after_seq)
          sub_id = next_sub_id
          sub = Subscription.new(id: sub_id, session_id: session_id)
          replay.each { |e| sub.enqueue(e) }
          (@subscriptions[session_id] ||= []) << sub
          sub
        end
      end

      private

      def next_sub_id
        @sub_id_counter += 1
      end

      def publish(event)
        subs = @subscriptions[event.session_id]
        return unless subs
        subs.reject!(&:closed?)
        subs.each { |sub| sub.enqueue(event) }
      end

      def assert_open!(record)
        case record.status
        when :closed
          raise InvalidTransitionError, "Session #{record.id} is closed"
        when :aborted
          raise InvalidTransitionError, "Session #{record.id} is aborted"
        end
      end

      def current_state(session_id)
        State.reduce(session_id, @store.events(session_id))
      end
    end
  end
end
