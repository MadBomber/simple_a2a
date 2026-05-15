# frozen_string_literal: true

require "test_helper"

class TestTaskBroadcast < Minitest::Test
  def setup
    @broadcast = A2A::Server::TaskBroadcast.new
  end


  def make_status_event(task_id = "t-1")
    A2A::Models::TaskStatusUpdateEvent.new(
      task_id: task_id,
      context_id: "c-1",
      status: A2A::Models::TaskStatus.new(state: "working", timestamp: "2026-01-01T00:00:00Z")
    )
  end


  def test_subscribe_returns_a_ractor_queue
    q = @broadcast.subscribe
    assert_instance_of RactorQueue, q
  end


  def test_publish_delivers_to_subscriber
    q     = @broadcast.subscribe
    event = make_status_event
    @broadcast.publish("t-1", event)
    received = q.try_pop
    refute received.equal?(RactorQueue::EMPTY)
    assert_equal event, received
  end


  def test_publish_delivers_to_multiple_subscribers
    q1 = @broadcast.subscribe
    q2 = @broadcast.subscribe
    event = make_status_event
    @broadcast.publish("t-1", event)
    assert_equal event, q1.try_pop
    assert_equal event, q2.try_pop
  end


  def test_publish_task_id_is_ignored
    q = @broadcast.subscribe
    event = make_status_event
    @broadcast.publish("any-id", event)
    assert_equal event, q.try_pop
  end


  def test_close_pushes_done_sentinel_to_all_subscribers
    q1 = @broadcast.subscribe
    q2 = @broadcast.subscribe
    @broadcast.close
    assert q1.try_pop.equal?(A2A::Server::TaskBroadcast::DONE)
    assert q2.try_pop.equal?(A2A::Server::TaskBroadcast::DONE)
  end


  def test_error_pushes_broadcast_error_to_all_subscribers
    q1 = @broadcast.subscribe
    q2 = @broadcast.subscribe
    @broadcast.error("boom")
    ev1 = q1.try_pop
    ev2 = q2.try_pop
    assert_instance_of A2A::Server::TaskBroadcast::BroadcastError, ev1
    assert_equal "boom", ev1.message
    assert_instance_of A2A::Server::TaskBroadcast::BroadcastError, ev2
  end


  def test_unsubscribe_stops_delivery
    q = @broadcast.subscribe
    @broadcast.unsubscribe(q)
    @broadcast.publish("t-1", make_status_event)
    assert q.try_pop.equal?(RactorQueue::EMPTY)
  end


  def test_publish_with_no_subscribers_does_not_raise
    @broadcast.publish("t-1", make_status_event)
    assert true
  end


  def test_close_with_no_subscribers_does_not_raise
    @broadcast.close
    assert true
  end
end


class TestBroadcastRegistry < Minitest::Test
  def setup
    @registry = A2A::Server::BroadcastRegistry.new
  end


  def test_find_returns_nil_for_unknown_task
    assert_nil @registry.find("t-1")
  end


  def test_register_and_find
    broadcast = A2A::Server::TaskBroadcast.new
    @registry.register("t-1", broadcast)
    assert_equal broadcast, @registry.find("t-1")
  end


  def test_unregister_removes_entry
    broadcast = A2A::Server::TaskBroadcast.new
    @registry.register("t-1", broadcast)
    @registry.unregister("t-1")
    assert_nil @registry.find("t-1")
  end


  def test_different_tasks_are_isolated
    b1 = A2A::Server::TaskBroadcast.new
    b2 = A2A::Server::TaskBroadcast.new
    @registry.register("t-1", b1)
    @registry.register("t-2", b2)
    assert_equal b1, @registry.find("t-1")
    assert_equal b2, @registry.find("t-2")
  end
end
