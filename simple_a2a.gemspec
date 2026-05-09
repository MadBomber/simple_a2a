# frozen_string_literal: true

require_relative "lib/simple_a2a/version"

Gem::Specification.new do |spec|
  spec.name = "simple_a2a"
  spec.version = A2A::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dvanhoozer@gmail.com"]

  spec.summary = "A Ruby implementation of the Agent2Agent (A2A) protocol"
  spec.description = "Client and server for the A2A protocol — async-first, Rack-compatible, built on Falcon."
  spec.homepage = "https://github.com/MadBomber/simple_a2a"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "zeitwerk",    "~> 2.6"
  spec.add_dependency "logger",      "~> 1.6"
  spec.add_dependency "async",       "~> 2.0"
  spec.add_dependency "async-http",  "~> 0.66"
  spec.add_dependency "falcon",      "~> 0.47"
  spec.add_dependency "roda",        "~> 3.0"
  spec.add_dependency "rack",        "~> 3.0"
  spec.add_dependency "jwt",         "~> 2.0"
  spec.add_dependency "ractor_queue", "~> 0.2"

  spec.add_development_dependency "rake",               "~> 13.0"
  spec.add_development_dependency "minitest",           "~> 5.0"
  spec.add_development_dependency "minitest-reporters", "~> 1.6"
  spec.add_development_dependency "rack-test",          "~> 2.0"
  spec.add_development_dependency "debug_me"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "simplecov-ai"
end
