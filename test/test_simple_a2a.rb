# frozen_string_literal: true

require "test_helper"

class TestA2A < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::A2A::VERSION
  end

  def test_logger_accessor
    A2A.logger = nil
    assert_nil A2A.logger
  end
end
