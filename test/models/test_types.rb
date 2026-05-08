# frozen_string_literal: true

require "test_helper"

class TestTypes < Minitest::Test
  def test_task_state_terminal
    assert_includes SimpleA2a::Models::Types::TaskState::TERMINAL, "completed"
    assert_includes SimpleA2a::Models::Types::TaskState::TERMINAL, "failed"
    assert_includes SimpleA2a::Models::Types::TaskState::TERMINAL, "canceled"
    assert_includes SimpleA2a::Models::Types::TaskState::TERMINAL, "rejected"
  end

  def test_task_state_interrupted
    assert_includes SimpleA2a::Models::Types::TaskState::INTERRUPTED, "input_required"
    assert_includes SimpleA2a::Models::Types::TaskState::INTERRUPTED, "auth_required"
  end

  def test_task_state_active
    assert_includes SimpleA2a::Models::Types::TaskState::ACTIVE, "submitted"
    assert_includes SimpleA2a::Models::Types::TaskState::ACTIVE, "working"
  end

  def test_terminal_predicate
    assert SimpleA2a::Models::Types::TaskState.terminal?("completed")
    refute SimpleA2a::Models::Types::TaskState.terminal?("working")
  end

  def test_interrupted_predicate
    assert SimpleA2a::Models::Types::TaskState.interrupted?("input_required")
    refute SimpleA2a::Models::Types::TaskState.interrupted?("completed")
  end

  def test_role_constants
    assert_equal "user",  SimpleA2a::Models::Types::Role::USER
    assert_equal "agent", SimpleA2a::Models::Types::Role::AGENT
  end
end
