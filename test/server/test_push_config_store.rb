# frozen_string_literal: true

require "test_helper"

class TestPushConfigStore < Minitest::Test
  def setup
    @store  = A2A::Server::PushConfigStore.new
    @config = A2A::Models::PushNotificationConfig.new(webhook_url: "https://example.com/cb")
  end


  def test_get_returns_nil_when_empty
    assert_nil @store.get("task-1")
  end


  def test_set_stores_and_returns_config
    result = @store.set("task-1", @config)
    assert_same @config, result
    assert_same @config, @store.get("task-1")
  end


  def test_get_returns_nil_for_unknown_task_id
    @store.set("task-1", @config)
    assert_nil @store.get("task-2")
  end


  def test_set_overwrites_existing_entry
    config2 = A2A::Models::PushNotificationConfig.new(webhook_url: "https://other.example.com/cb")
    @store.set("task-1", @config)
    @store.set("task-1", config2)
    assert_same config2, @store.get("task-1")
  end


  def test_delete_removes_entry
    @store.set("task-1", @config)
    @store.delete("task-1")
    assert_nil @store.get("task-1")
  end


  def test_delete_is_a_noop_for_missing_key
    assert_nil @store.delete("nonexistent")
  end


  def test_list_returns_empty_hash_when_empty
    assert_equal({}, @store.list)
  end


  def test_list_returns_all_entries
    config2 = A2A::Models::PushNotificationConfig.new(webhook_url: "https://b.example.com/cb")
    @store.set("task-1", @config)
    @store.set("task-2", config2)
    listing = @store.list
    assert_equal 2, listing.size
    assert_same @config, listing["task-1"]
    assert_same config2, listing["task-2"]
  end


  def test_list_returns_a_snapshot_not_live_reference
    @store.set("task-1", @config)
    listing = @store.list
    @store.delete("task-1")
    assert_equal 1, listing.size
  end
end
