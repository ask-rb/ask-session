# frozen_string_literal: true

require_relative "test_helper"

class RecordTest < Minitest::Test
  include TestHelpers

  def test_record_is_immutable
    record = build_record
    assert_instance_of Ask::Session::Record, record
    assert_equal "sess_001", record.id
    assert_equal :active, record.status
    assert_equal({}, record.metadata)
    assert_equal 0, record.version
  end

  def test_record_create_with_defaults
    record = Ask::Session::Record.create
    assert record.id.start_with?("sess_")
    assert_equal :active, record.status
    assert_equal({}, record.metadata)
    assert_equal 0, record.version
  end

  def test_record_create_with_explicit_id
    record = Ask::Session::Record.create(id: "custom_id")
    assert_equal "custom_id", record.id
  end

  def test_record_with_updates_returns_new_instance
    record = build_record
    updated = record.with_updates(status: :completed, version: 1)
    assert_equal :completed, updated.status
    assert_equal 1, updated.version
    assert_equal :active, record.status
    assert_equal 0, record.version
  end

  def test_record_with_updates_sets_updated_at
    record = build_record
    now = Time.utc(2026, 6, 15)
    updated = record.with_updates(updated_at: now)
    assert_equal now, updated.updated_at
  end

  def test_record_keyword_init
    record = Ask::Session::Record.new(
      id: "s1", status: :active, metadata: { key: "val" },
      created_at: Time.now, updated_at: Time.now, version: 0
    )
    assert_equal "s1", record.id
    assert_equal({ key: "val" }, record.metadata)
  end

  def test_record_equality
    now = Time.utc(2026, 1, 1)
    r1 = Ask::Session::Record.new(id: "s1", status: :active, metadata: {}, created_at: now, updated_at: now, version: 0)
    r2 = Ask::Session::Record.new(id: "s1", status: :active, metadata: {}, created_at: now, updated_at: now, version: 0)
    assert_equal r1, r2
  end
end
