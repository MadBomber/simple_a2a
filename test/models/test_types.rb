# frozen_string_literal: true

require "test_helper"

class TestTypes < Minitest::Test
  def test_task_state_terminal
    assert_includes A2A::Models::Types::TaskState::TERMINAL, "completed"
    assert_includes A2A::Models::Types::TaskState::TERMINAL, "failed"
    assert_includes A2A::Models::Types::TaskState::TERMINAL, "canceled"
    assert_includes A2A::Models::Types::TaskState::TERMINAL, "rejected"
  end


  def test_task_state_interrupted
    assert_includes A2A::Models::Types::TaskState::INTERRUPTED, "input_required"
    assert_includes A2A::Models::Types::TaskState::INTERRUPTED, "auth_required"
  end


  def test_task_state_active
    assert_includes A2A::Models::Types::TaskState::ACTIVE, "submitted"
    assert_includes A2A::Models::Types::TaskState::ACTIVE, "working"
  end


  def test_terminal_predicate
    assert A2A::Models::Types::TaskState.terminal?("completed")
    refute A2A::Models::Types::TaskState.terminal?("working")
  end


  def test_interrupted_predicate
    assert A2A::Models::Types::TaskState.interrupted?("input_required")
    refute A2A::Models::Types::TaskState.interrupted?("completed")
  end


  def test_role_constants
    assert_equal "user",  A2A::Models::Types::Role::USER
    assert_equal "agent", A2A::Models::Types::Role::AGENT
  end
end
