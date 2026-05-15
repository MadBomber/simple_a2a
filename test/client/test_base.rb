# frozen_string_literal: true

require "test_helper"

class TestClientBase < Minitest::Test
  def setup
    @client = A2A::Client::Base.new(url: "http://localhost:9292")
  end


  def stub_http_post(result_or_error, &)
    body = if result_or_error.key?(:error)
             JSON.generate({ "jsonrpc" => "2.0", "id" => "1", "error" => result_or_error[:error] })
           else
             JSON.generate({ "jsonrpc" => "2.0", "id" => "1", "result" => result_or_error[:result] })
           end
    @client.stub(:http_post, body, &)
  end


  def stub_http_get(body_hash, &)
    @client.stub(:http_get, JSON.generate(body_hash), &)
  end


  def task_hash(state: "completed")
    {
      "id" => "task-1",
      "contextId" => "ctx-1",
      "status" => { "state" => state, "timestamp" => "2026-01-01T00:00:00Z" },
      "artifacts" => [],
      "metadata" => {},
      "kind" => "task"
    }
  end


  def agent_card_hash
    {
      "name" => "TestAgent",
      "version" => "1.0",
      "capabilities" => {},
      "skills" => [],
      "interfaces" => []
    }
  end

  # --- agent_card ---

  def test_agent_card_returns_agent_card
    stub_http_get(agent_card_hash) do
      card = @client.agent_card
      assert_kind_of A2A::Models::AgentCard, card
      assert_equal "TestAgent", card.name
    end
  end

  # --- send_task ---

  def test_send_task_returns_task
    stub_http_post(result: task_hash) do
      msg  = A2A::Models::Message.user("hello")
      task = @client.send_task(message: msg)
      assert_kind_of A2A::Models::Task, task
      assert_equal "task-1", task.id
    end
  end


  def test_send_task_accepts_hash_message
    stub_http_post(result: task_hash) do
      msg_hash = A2A::Models::Message.user("hi").to_h
      task     = @client.send_task(message: msg_hash)
      assert_kind_of A2A::Models::Task, task
    end
  end


  def test_send_task_with_task_id_option
    captured_json = nil
    @client.stub(:http_post, lambda { |body|
      captured_json = JSON.parse(body)
      JSON.generate({ "jsonrpc" => "2.0", "id" => "x", "result" => task_hash })
    }) do
      @client.send_task(message: A2A::Models::Message.user("hi"), task_id: "my-id")
    end
    assert_equal "my-id", captured_json["params"]["id"]
  end


  def test_send_task_raises_on_error
    err = { "code" => -32_001, "message" => "not found" }
    stub_http_post(error: err) do
      assert_raises(A2A::Error) do
        @client.send_task(message: A2A::Models::Message.user("hi"))
      end
    end
  end

  # --- get_task ---

  def test_get_task_returns_task
    stub_http_post(result: task_hash) do
      task = @client.get_task("task-1")
      assert_kind_of A2A::Models::Task, task
      assert_equal "task-1", task.id
    end
  end


  def test_get_task_raises_on_error
    err = { "code" => -32_001, "message" => "Task not found" }
    stub_http_post(error: err) do
      assert_raises(A2A::Error) { @client.get_task("no-such") }
    end
  end

  # --- list_tasks ---

  def test_list_tasks_returns_array
    stub_http_post(result: [task_hash]) do
      tasks = @client.list_tasks
      assert_kind_of Array, tasks
      assert_equal 1, tasks.length
      assert_kind_of A2A::Models::Task, tasks.first
    end
  end


  def test_list_tasks_empty
    stub_http_post(result: []) do
      assert_equal [], @client.list_tasks
    end
  end

  # --- cancel_task ---

  def test_cancel_task_returns_task
    stub_http_post(result: task_hash(state: "canceled")) do
      task = @client.cancel_task("task-1")
      assert_kind_of A2A::Models::Task, task
    end
  end

  # --- rpc_call error handling ---

  def test_rpc_error_raises_a2a_error
    err = { "code" => -32_603, "message" => "Internal error" }
    stub_http_post(error: err) do
      assert_raises(A2A::Error) { @client.list_tasks }
    end
  end
end
