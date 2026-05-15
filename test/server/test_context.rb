# frozen_string_literal: true

require "test_helper"

class FakeEventRouter
  attr_reader :published

  def initialize
    @published = []
  end


  def publish(task_id, event)
    @published << [task_id, event]
  end
end


class TestServerContext < Minitest::Test
  def setup
    @storage  = A2A::Storage::Memory.new
    @router   = FakeEventRouter.new
    @task     = A2A::Models::Task.new(
      id: "t-1", context_id: "c-1",
      status: A2A::Models::TaskStatus.new(state: "submitted")
    )
    @message  = A2A::Models::Message.user("hello")
    @ctx      = A2A::Server::Context.new(
      task: @task, message: @message,
      storage: @storage, event_router: @router
    )
  end


  def test_accessors
    assert_equal @task,    @ctx.task
    assert_equal @message, @ctx.message
    assert_equal @storage, @ctx.storage
    assert_equal @router,  @ctx.event_router
    assert_equal({},       @ctx.config)
  end


  def test_save_task
    @ctx.save_task
    assert_equal @task, @storage.find("t-1")
  end


  def test_emit_status_publishes_event_and_saves
    @task.start!
    @ctx.emit_status
    assert_equal 1, @router.published.length
    task_id, event = @router.published.first
    assert_equal "t-1", task_id
    assert_instance_of A2A::Models::TaskStatusUpdateEvent, event
    assert_equal "working", event.status.state
    refute event.final?
    assert_equal @task, @storage.find("t-1")
  end


  def test_emit_status_final
    @task.complete!
    @ctx.emit_status(final: true)
    _, event = @router.published.first
    assert event.final?
  end


  def test_emit_artifact_publishes_event
    art = A2A::Models::Artifact.new(
      artifact_id: "art-1",
      parts: [A2A::Models::Part.text("result")]
    )
    @ctx.emit_artifact(art, last_chunk: true)
    assert_equal 1, @router.published.length
    _, event = @router.published.first
    assert_instance_of A2A::Models::TaskArtifactUpdateEvent, event
    assert_equal "art-1", event.artifact.artifact_id
    assert event.last_chunk?
    refute event.append?
  end


  def test_custom_config
    ctx = A2A::Server::Context.new(
      task: @task, message: @message,
      storage: @storage, event_router: @router,
      config: { timeout: 30 }
    )
    assert_equal({ timeout: 30 }, ctx.config)
  end
end


class TestResumeContext < Minitest::Test
  def setup
    @storage      = A2A::Storage::Memory.new
    @router       = FakeEventRouter.new
    @task         = A2A::Models::Task.new(
      id: "t-1", context_id: "c-1",
      status: A2A::Models::TaskStatus.new(state: "input_required")
    )
    @message      = A2A::Models::Message.user("original")
    @resume_msg   = A2A::Models::Message.user("here is the input")
  end


  def test_resume_message_accessible
    ctx = A2A::Server::ResumeContext.new(
      task: @task, message: @message,
      storage: @storage, event_router: @router,
      resume_message: @resume_msg
    )
    assert_equal @resume_msg, ctx.resume_message
    assert_equal @message,    ctx.message
  end
end


class TestAgentExecutor < Minitest::Test
  def setup
    @storage = A2A::Storage::Memory.new
    @router  = FakeEventRouter.new
    @task    = A2A::Models::Task.new(
      id: "t-1", context_id: "c-1",
      status: A2A::Models::TaskStatus.new(state: "submitted")
    )
    @ctx = A2A::Server::Context.new(
      task: @task, message: A2A::Models::Message.user("hi"),
      storage: @storage, event_router: @router
    )
  end


  def test_call_raises_not_implemented
    executor = A2A::Server::AgentExecutor.new
    assert_raises(NotImplementedError) { executor.call(@ctx) }
  end


  def test_cancel_transitions_to_canceled
    executor = A2A::Server::AgentExecutor.new
    executor.cancel(@ctx)
    assert_equal "canceled", @task.state
    assert_equal 1, @router.published.length
    _, event = @router.published.first
    assert event.final?
    assert_equal "canceled", event.status.state
  end


  def test_subclass_can_implement_call
    executor = Class.new(A2A::Server::AgentExecutor) do
      def call(ctx)
        ctx.task.complete!
      end
    end.new
    executor.call(@ctx)
    assert_equal "completed", @task.state
  end
end
