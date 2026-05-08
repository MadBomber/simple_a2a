# frozen_string_literal: true

require "test_helper"

class TestStorageMemory < Minitest::Test
  def setup
    @store = A2A::Storage::Memory.new
    @task  = A2A::Models::Task.new(
      id: "t-1",
      status: A2A::Models::TaskStatus.new(state: "submitted")
    )
  end

  def test_save_and_find
    @store.save(@task)
    found = @store.find("t-1")
    assert_equal @task, found
  end

  def test_find_returns_nil_for_missing
    assert_nil @store.find("no-such-id")
  end

  def test_find_bang_raises_for_missing
    assert_raises(A2A::TaskNotFoundError) do
      @store.find!("no-such-id")
    end
  end

  def test_find_bang_returns_task_when_found
    @store.save(@task)
    assert_equal @task, @store.find!("t-1")
  end

  def test_delete_removes_task
    @store.save(@task)
    @store.delete("t-1")
    assert_nil @store.find("t-1")
  end

  def test_delete_missing_is_noop
    @store.delete("no-such-id")
    assert_equal 0, @store.size
  end

  def test_list_returns_all_tasks
    task2 = A2A::Models::Task.new(
      id: "t-2",
      status: A2A::Models::TaskStatus.new(state: "working")
    )
    @store.save(@task)
    @store.save(task2)
    ids = @store.list.map(&:id)
    assert_includes ids, "t-1"
    assert_includes ids, "t-2"
  end

  def test_list_returns_empty_when_empty
    assert_equal [], @store.list
  end

  def test_size
    assert_equal 0, @store.size
    @store.save(@task)
    assert_equal 1, @store.size
  end

  def test_clear_empties_store
    @store.save(@task)
    @store.clear
    assert_equal 0, @store.size
  end

  def test_save_overwrites_existing
    @store.save(@task)
    @task.start!
    @store.save(@task)
    assert_equal "working", @store.find("t-1").state
    assert_equal 1, @store.size
  end

  def test_list_returns_independent_snapshot
    @store.save(@task)
    snapshot = @store.list
    @store.clear
    assert_equal 1, snapshot.length
  end
end
