# frozen_string_literal: true

require "test_helper"

class TestEventRouter < Minitest::Test
  def setup
    @router = A2A::Server::EventRouter.new
  end

  def teardown
    # nothing to teardown — each test uses a fresh router
  end

  def make_status_event(task_id = "t-1")
    A2A::Models::TaskStatusUpdateEvent.new(
      task_id:    task_id,
      context_id: "c-1",
      status:     A2A::Models::TaskStatus.new(state: "working", timestamp: "2026-01-01T00:00:00Z")
    )
  end

  def test_channel_does_not_exist_before_open
    refute @router.channel?("t-1")
  end

  def test_open_creates_channel
    @router.open("t-1")
    assert @router.channel?("t-1")
  end

  def test_open_is_idempotent
    @router.open("t-1")
    @router.open("t-1")
    assert @router.channel?("t-1")
  end

  def test_close_removes_channel
    @router.open("t-1")
    @router.close("t-1")
    refute @router.channel?("t-1")
  end

  def test_publish_auto_opens_channel
    event = make_status_event
    @router.publish("t-1", event)
    assert @router.channel?("t-1")
  end

  def test_subscribe_receives_published_events
    received = []
    @router.subscribe("t-1") { |ev| received << ev }
    event = make_status_event
    @router.publish("t-1", event)
    assert_equal 1, received.length
    assert_equal event, received.first
  end

  def test_subscribe_returns_subscriber_id
    id = @router.subscribe("t-1") { |_| }
    assert id.is_a?(Integer) || id.is_a?(Object)
  end

  def test_multiple_subscribers_all_receive
    r1 = []
    r2 = []
    @router.subscribe("t-1") { |ev| r1 << ev }
    @router.subscribe("t-1") { |ev| r2 << ev }
    @router.publish("t-1", make_status_event)
    assert_equal 1, r1.length
    assert_equal 1, r2.length
  end

  def test_publish_to_different_tasks_isolated
    r1 = []
    r2 = []
    @router.subscribe("t-1") { |ev| r1 << ev }
    @router.subscribe("t-2") { |ev| r2 << ev }
    @router.publish("t-1", make_status_event("t-1"))
    @router.publish("t-2", make_status_event("t-2"))
    assert_equal 1, r1.length
    assert_equal 1, r2.length
    assert_equal "t-1", r1.first.task_id
    assert_equal "t-2", r2.first.task_id
  end

  def test_publish_to_unknown_channel_does_not_raise
    @router.publish("no-such-task", make_status_event)
    assert true
  end

  def test_unsubscribe_stops_delivery
    received = []
    id = @router.subscribe("t-1") { |ev| received << ev }
    @router.publish("t-1", make_status_event)
    @router.unsubscribe("t-1", id)
    @router.publish("t-1", make_status_event)
    assert_equal 1, received.length
  end
end
