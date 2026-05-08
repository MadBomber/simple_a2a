# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create do |t|
  # Load SimpleCov before minitest/autorun so its at_exit fires AFTER
  # Minitest's (LIFO order), meaning coverage is reported after tests run.
  t.test_prelude = %(require_relative "test/test_helper")
  t.framework    = ""  # test_helper already requires minitest/autorun
end

task default: :test
