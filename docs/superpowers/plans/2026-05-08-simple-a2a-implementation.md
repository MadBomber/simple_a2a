# simple_a2a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `simple_a2a` Ruby gem — a full Agent2Agent (A2A) protocol client and server built on the async fiber ecosystem.

**Architecture:** Standalone Rack gem with JSON-RPC 2.0 + HTTP+REST bindings. Server uses Falcon + Roda with TypedBus for per-task SSE event fan-out. Client uses async-http throughout. Data model mirrors the A2A spec with camelCase ↔ snake_case serialization handled by a shared `Models::Base` DSL.

**Tech Stack:** Ruby 3.2+, async, async-http, falcon, roda, rack, jwt, simple_flow, typed_bus, minitest

---

## File Map

| File | Responsibility |
|------|---------------|
| `simple_a2a.gemspec` | Declare all runtime + dev dependencies |
| `Gemfile` | Add minitest-reporters dev dep |
| `lib/simple_a2a.rb` | Top-level requires + convenience aliases |
| `lib/simple_a2a/errors.rb` | All A2A exception classes |
| `lib/simple_a2a/models/base.rb` | `attribute` DSL, `from_hash`, `to_h`, `valid?` |
| `lib/simple_a2a/models/types.rb` | `TaskState`, `Role`, `BindingType` enums |
| `lib/simple_a2a/models/part.rb` | `Part` with OneOf content + factories |
| `lib/simple_a2a/models/message.rb` | `Message` with role, parts[], factories |
| `lib/simple_a2a/models/artifact.rb` | `Artifact` — task output |
| `lib/simple_a2a/models/task_status.rb` | `TaskStatus` wrapping `TaskState` |
| `lib/simple_a2a/models/task.rb` | `Task` with state transition methods |
| `lib/simple_a2a/models/stream_response.rb` | OneOf SSE envelope |
| `lib/simple_a2a/models/send_message_config.rb` | `SendMessageConfiguration` |
| `lib/simple_a2a/models/push_notification.rb` | `PushNotificationConfig` + `AuthenticationInfo` |
| `lib/simple_a2a/models/agent_card.rb` | `AgentCard`, `AgentProvider`, `AgentCapabilities`, `AgentSkill`, `AgentInterface` |
| `lib/simple_a2a/models/security_scheme.rb` | Polymorphic security schemes |
| `lib/simple_a2a/events/task_status_update.rb` | `TaskStatusUpdateEvent` + SSE format |
| `lib/simple_a2a/events/task_artifact_update.rb` | `TaskArtifactUpdateEvent` + SSE format |
| `lib/simple_a2a/jsonrpc/error.rb` | Error codes + `JSONRPC::Error` struct |
| `lib/simple_a2a/jsonrpc/request.rb` | Parse + build JSON-RPC 2.0 request |
| `lib/simple_a2a/jsonrpc/response.rb` | Build success/error JSON-RPC 2.0 response |
| `lib/simple_a2a/storage/base.rb` | Abstract storage interface |
| `lib/simple_a2a/storage/memory.rb` | Async-safe in-memory storage |
| `lib/simple_a2a/server/agent_executor.rb` | Abstract executor base class |
| `lib/simple_a2a/server/context.rb` | `Context` + `ResumeContext` |
| `lib/simple_a2a/server/event_router.rb` | TypedBus wrapper for per-task fan-out |
| `lib/simple_a2a/server/push_sender.rb` | Outbound webhook delivery + JWT signing |
| `lib/simple_a2a/server/falcon_runner.rb` | Falcon startup (lifted from simple_acp) |
| `lib/simple_a2a/server/app.rb` | Roda routes: JSON-RPC + HTTP+REST |
| `lib/simple_a2a/server/base.rb` | Wires executor, storage, router, app |
| `lib/simple_a2a/client/sse.rb` | async-http SSE stream → `StreamResponse` |
| `lib/simple_a2a/client/base.rb` | All 11 A2A operations via async-http |

---

## Task 1: Gemspec, Gemfile, Errors, Top-level Module

**Files:**
- Modify: `simple_a2a.gemspec`
- Modify: `Gemfile`
- Create: `lib/simple_a2a/errors.rb`
- Modify: `lib/simple_a2a.rb`
- Modify: `test/test_helper.rb`

- [ ] **Step 1: Update gemspec with all dependencies**

Replace the contents of `simple_a2a.gemspec`:

```ruby
# frozen_string_literal: true

require_relative "lib/simple_a2a/version"

Gem::Specification.new do |spec|
  spec.name = "simple_a2a"
  spec.version = SimpleA2a::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dvanhoozer@gmail.com"]

  spec.summary = "A Ruby implementation of the Agent2Agent (A2A) protocol"
  spec.description = "Client and server for the A2A protocol — async-first, Rack-compatible, built on Falcon and TypedBus."
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

  spec.add_dependency "async",       "~> 2.0"
  spec.add_dependency "async-http",  "~> 0.66"
  spec.add_dependency "falcon",      "~> 0.47"
  spec.add_dependency "roda",        "~> 3.0"
  spec.add_dependency "rack",        "~> 3.0"
  spec.add_dependency "jwt",         "~> 2.0"
  spec.add_dependency "simple_flow", "~> 0.4"
  spec.add_dependency "typed_bus",   "~> 0.0"

  spec.add_development_dependency "rake",               "~> 13.0"
  spec.add_development_dependency "minitest",           "~> 5.0"
  spec.add_development_dependency "minitest-reporters", "~> 1.6"
  spec.add_development_dependency "rack-test",          "~> 2.0"
  spec.add_development_dependency "debug_me"
end
```

- [ ] **Step 2: Update Gemfile**

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "irb"
```

- [ ] **Step 3: Install dependencies**

```bash
bundle install
```

Expected: All gems install successfully. No errors.

- [ ] **Step 4: Write failing test for errors**

Create `test/test_errors.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  def test_base_error_is_standard_error
    assert_operator SimpleA2a::Error, :<, StandardError
  end

  def test_all_errors_inherit_from_base
    [
      SimpleA2a::ConfigurationError,
      SimpleA2a::TaskNotFoundError,
      SimpleA2a::TaskNotCancelableError,
      SimpleA2a::PushNotificationNotSupportedError,
      SimpleA2a::UnsupportedOperationError,
      SimpleA2a::ContentTypeNotSupportedError,
      SimpleA2a::InvalidAgentResponseError,
      SimpleA2a::ExtensionSupportRequiredError,
      SimpleA2a::VersionNotSupportedError,
      SimpleA2a::ExtendedAgentCardNotConfiguredError
    ].each do |klass|
      assert_operator klass, :<, SimpleA2a::Error, "#{klass} should inherit from SimpleA2a::Error"
    end
  end
end
```

- [ ] **Step 5: Run test to verify it fails**

```bash
bundle exec ruby -Ilib -Itest test/test_errors.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Error`

- [ ] **Step 6: Create errors.rb**

Create `lib/simple_a2a/errors.rb`:

```ruby
# frozen_string_literal: true

module SimpleA2a
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TaskNotFoundError < Error; end
  class TaskNotCancelableError < Error; end
  class PushNotificationNotSupportedError < Error; end
  class UnsupportedOperationError < Error; end
  class ContentTypeNotSupportedError < Error; end
  class InvalidAgentResponseError < Error; end
  class ExtensionSupportRequiredError < Error; end
  class VersionNotSupportedError < Error; end
  class ExtendedAgentCardNotConfiguredError < Error; end
end
```

- [ ] **Step 7: Update lib/simple_a2a.rb**

```ruby
# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

require_relative "simple_a2a/version"
require_relative "simple_a2a/errors"

module SimpleA2a
  class << self
    attr_accessor :logger
  end
end
```

- [ ] **Step 8: Update test/test_helper.rb**

```ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "simple_a2a"
require "minitest/autorun"
require "minitest/reporters"

Minitest::Reporters.use! Minitest::Reporters::DefaultReporter.new(color: true)
```

- [ ] **Step 9: Run test to verify it passes**

```bash
bundle exec ruby -Ilib -Itest test/test_errors.rb
```

Expected: `1 runs, 2 assertions, 0 failures, 0 errors`

- [ ] **Step 10: Commit**

```bash
git add simple_a2a.gemspec Gemfile lib/simple_a2a.rb lib/simple_a2a/errors.rb test/test_helper.rb test/test_errors.rb
git commit -m "feat: scaffold gemspec, errors, and top-level module"
```

---

## Task 2: Models::Base

**Files:**
- Create: `lib/simple_a2a/models/base.rb`
- Create: `test/models/test_base.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_base.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestModelsBase < Minitest::Test
  # Minimal subclass for testing
  class Widget < SimpleA2a::Models::Base
    attribute :widget_id, required: true
    attribute :name
    attribute :count, default: 0
    attribute :tags, default: -> { [] }
  end

  def test_attribute_dsl_creates_accessors
    w = Widget.new(widget_id: "abc")
    assert_respond_to w, :widget_id
    assert_respond_to w, :widget_id=
  end

  def test_required_attribute_set
    w = Widget.new(widget_id: "abc")
    assert_equal "abc", w.widget_id
  end

  def test_default_value
    w = Widget.new(widget_id: "x")
    assert_equal 0, w.count
  end

  def test_default_proc_is_fresh_per_instance
    w1 = Widget.new(widget_id: "x")
    w2 = Widget.new(widget_id: "y")
    w1.tags << "a"
    assert_empty w2.tags
  end

  def test_valid_when_required_present
    w = Widget.new(widget_id: "abc")
    assert w.valid?
  end

  def test_invalid_when_required_missing
    w = Widget.new
    refute w.valid?
  end

  def test_from_hash_camel_case_keys
    w = Widget.from_hash({ "widgetId" => "xyz", "name" => "Foo", "count" => 3 })
    assert_equal "xyz", w.widget_id
    assert_equal "Foo", w.name
    assert_equal 3, w.count
  end

  def test_from_hash_snake_case_keys
    w = Widget.from_hash({ widget_id: "xyz" })
    assert_equal "xyz", w.widget_id
  end

  def test_from_hash_nil_returns_nil
    assert_nil Widget.from_hash(nil)
  end

  def test_to_h_uses_camel_case_keys
    w = Widget.new(widget_id: "abc", name: "Bob")
    h = w.to_h
    assert_equal "abc", h["widgetId"]
    assert_equal "Bob", h["name"]
  end

  def test_to_h_omits_nil_values
    w = Widget.new(widget_id: "abc")
    refute w.to_h.key?("name")
  end

  def test_to_json_round_trips
    w = Widget.new(widget_id: "abc", name: "Test", count: 5)
    parsed = JSON.parse(w.to_json)
    assert_equal "abc", parsed["widgetId"]
    assert_equal 5, parsed["count"]
  end

  def test_equality
    w1 = Widget.new(widget_id: "x", name: "foo")
    w2 = Widget.new(widget_id: "x", name: "foo")
    assert_equal w1, w2
  end

  def test_inequality
    w1 = Widget.new(widget_id: "x")
    w2 = Widget.new(widget_id: "y")
    refute_equal w1, w2
  end

  def test_subclass_inherits_attributes
    class SubWidget < Widget
      attribute :extra
    end
    assert_includes SubWidget.attributes.keys, :widget_id
    assert_includes SubWidget.attributes.keys, :extra
  end

  def test_nested_model_coercion
    class Inner < SimpleA2a::Models::Base
      attribute :value
    end
    class Outer < SimpleA2a::Models::Base
      attribute :inner, type: Inner
    end

    outer = Outer.from_hash({ "inner" => { "value" => "hello" } })
    assert_instance_of Inner, outer.inner
    assert_equal "hello", outer.inner.value
  end

  def test_array_of_models_coercion
    class Item < SimpleA2a::Models::Base
      attribute :label
    end
    class Container < SimpleA2a::Models::Base
      attribute :items, type: [Item], default: -> { [] }
    end

    c = Container.from_hash({ "items" => [{ "label" => "a" }, { "label" => "b" }] })
    assert_equal 2, c.items.length
    assert_instance_of Item, c.items[0]
    assert_equal "b", c.items[1].label
  end
end
```

- [ ] **Step 2: Create test directory and run to verify failure**

```bash
mkdir -p test/models
bundle exec ruby -Ilib -Itest test/models/test_base.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models`

- [ ] **Step 3: Create lib/simple_a2a/models/base.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class Base
      class << self
        def attribute(name, type: nil, default: nil, required: false)
          attributes[name] = { type: type, default: default, required: required }
          attr_accessor name
        end

        def attributes
          @attributes ||= {}
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@attributes, attributes.dup)
        end

        def from_hash(hash)
          return nil if hash.nil?
          kwargs = {}
          attributes.each do |name, opts|
            val = find_value(hash, name)
            next if val.nil?
            kwargs[name] = coerce(val, opts[:type])
          end
          new(**kwargs)
        end

        private

        def find_value(hash, name)
          camel = camelize(name)
          hash[camel] || hash[camel.to_sym] || hash[name.to_s] || hash[name]
        end

        def camelize(snake)
          parts = snake.to_s.split("_")
          (parts[0..0] + parts[1..].map(&:capitalize)).join
        end

        def coerce(val, type)
          return val if type.nil?

          if type.is_a?(Array)
            item_type = type[0]
            return val unless val.is_a?(Array)
            return val.map { |v| coerce(v, item_type) }
          end

          return val if val.is_a?(type)
          return type.from_hash(val) if val.is_a?(Hash) && type.respond_to?(:from_hash)
          val
        end
      end

      def initialize(**kwargs)
        self.class.attributes.each do |name, opts|
          val = kwargs.key?(name) ? kwargs[name] : resolve_default(opts[:default])
          send(:"#{name}=", val)
        end
      end

      def to_h
        self.class.attributes.each_with_object({}) do |(name, _), result|
          val = send(name)
          next if val.nil?
          result[camelize(name)] = serialize(val)
        end
      end

      def to_json(*)
        JSON.generate(to_h)
      end

      def valid?
        self.class.attributes.all? do |name, opts|
          !opts[:required] || !send(name).nil?
        end
      end

      def ==(other)
        return false unless other.is_a?(self.class)
        self.class.attributes.keys.all? { |n| send(n) == other.send(n) }
      end

      private

      def camelize(snake)
        parts = snake.to_s.split("_")
        (parts[0..0] + parts[1..].map(&:capitalize)).join
      end

      def resolve_default(default)
        default.respond_to?(:call) ? default.call : default
      end

      def serialize(val)
        case val
        when Base  then val.to_h
        when Array then val.map { |v| serialize(v) }
        when Hash  then val.transform_values { |v| serialize(v) }
        when Time  then val.iso8601
        else            val
        end
      end
    end
  end
end
```

- [ ] **Step 4: Add require to lib/simple_a2a.rb**

Add after the existing requires:

```ruby
require_relative "simple_a2a/models/base"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_base.rb
```

Expected: `17 runs, 24 assertions, 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add lib/simple_a2a/models/base.rb lib/simple_a2a.rb test/models/test_base.rb
git commit -m "feat: add Models::Base attribute DSL with camelCase serialization"
```

---

## Task 3: Models::Types

**Files:**
- Create: `lib/simple_a2a/models/types.rb`
- Create: `test/models/test_types.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_types.rb`:

```ruby
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
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/models/test_types.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models::Types`

- [ ] **Step 3: Create lib/simple_a2a/models/types.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    module Types
      module TaskState
        SUBMITTED      = "submitted"
        WORKING        = "working"
        COMPLETED      = "completed"
        FAILED         = "failed"
        CANCELED       = "canceled"
        REJECTED       = "rejected"
        INPUT_REQUIRED = "input_required"
        AUTH_REQUIRED  = "auth_required"

        TERMINAL    = [COMPLETED, FAILED, CANCELED, REJECTED].freeze
        INTERRUPTED = [INPUT_REQUIRED, AUTH_REQUIRED].freeze
        ACTIVE      = [SUBMITTED, WORKING].freeze
        ALL         = (TERMINAL + INTERRUPTED + ACTIVE).freeze

        def self.terminal?(state)    = TERMINAL.include?(state)
        def self.interrupted?(state) = INTERRUPTED.include?(state)
        def self.active?(state)      = ACTIVE.include?(state)
      end

      module Role
        USER  = "user"
        AGENT = "agent"
        ALL   = [USER, AGENT].freeze
      end

      module BindingType
        JSON_RPC = "json-rpc"
        HTTP     = "http"
        GRPC     = "grpc"
      end
    end
  end
end
```

- [ ] **Step 4: Add require to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/models/types"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_types.rb
```

Expected: `6 runs, 13 assertions, 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add lib/simple_a2a/models/types.rb lib/simple_a2a.rb test/models/test_types.rb
git commit -m "feat: add Models::Types enums for TaskState, Role, BindingType"
```

---

## Task 4: Models::Part

**Files:**
- Create: `lib/simple_a2a/models/part.rb`
- Create: `test/models/test_part.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_part.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestPart < Minitest::Test
  def test_text_factory
    p = SimpleA2a::Models::Part.text("hello")
    assert_equal "hello", p.text
    assert_equal "text/plain", p.media_type
    assert p.text?
    refute p.json?
  end

  def test_json_factory
    p = SimpleA2a::Models::Part.json({ key: "val" })
    assert_equal({ key: "val" }, p.data)
    assert_equal "application/json", p.media_type
    assert p.json?
  end

  def test_url_factory
    p = SimpleA2a::Models::Part.from_url("https://example.com/file.pdf", media_type: "application/pdf")
    assert_equal "https://example.com/file.pdf", p.url
    assert_equal "application/pdf", p.media_type
    assert p.url?
  end

  def test_binary_factory
    data = "\x89PNG\r\n"
    p = SimpleA2a::Models::Part.binary(data, media_type: "image/png")
    assert_equal Base64.strict_encode64(data), p.raw
    assert_equal "image/png", p.media_type
    assert p.raw?
  end

  def test_valid_requires_one_content_field
    p = SimpleA2a::Models::Part.new
    refute p.valid?
  end

  def test_to_h_text
    p = SimpleA2a::Models::Part.text("hi")
    h = p.to_h
    assert_equal "hi", h["text"]
    assert_equal "text/plain", h["mediaType"]
    refute h.key?("data")
  end

  def test_from_hash_text
    p = SimpleA2a::Models::Part.from_hash({ "text" => "world", "mediaType" => "text/plain" })
    assert_equal "world", p.text
    assert_equal "text/plain", p.media_type
  end

  def test_from_hash_json
    p = SimpleA2a::Models::Part.from_hash({ "data" => { "x" => 1 }, "mediaType" => "application/json" })
    assert_equal({ "x" => 1 }, p.data)
  end

  def test_round_trip
    original = SimpleA2a::Models::Part.text("round trip")
    restored = SimpleA2a::Models::Part.from_hash(JSON.parse(original.to_json))
    assert_equal original, restored
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/models/test_part.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models::Part`

- [ ] **Step 3: Create lib/simple_a2a/models/part.rb**

```ruby
# frozen_string_literal: true

require "base64"

module SimpleA2a
  module Models
    class Part < Base
      attribute :text
      attribute :raw
      attribute :url
      attribute :data
      attribute :media_type
      attribute :filename
      attribute :metadata

      def self.text(content, media_type: "text/plain", filename: nil)
        new(text: content, media_type: media_type, filename: filename)
      end

      def self.json(hash, filename: nil)
        new(data: hash, media_type: "application/json", filename: filename)
      end

      def self.from_url(url, media_type:, filename: nil)
        new(url: url, media_type: media_type, filename: filename)
      end

      def self.binary(bytes, media_type:, filename: nil)
        new(raw: Base64.strict_encode64(bytes), media_type: media_type, filename: filename)
      end

      def text?  = !text.nil?
      def json?  = !data.nil?
      def url?   = !url.nil?
      def raw?   = !raw.nil?

      def decoded_bytes
        return nil unless raw
        Base64.strict_decode64(raw)
      end

      def valid?
        content_fields = [text, raw, url, data].compact
        content_fields.length == 1
      end
    end
  end
end
```

- [ ] **Step 4: Add require to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/models/part"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_part.rb
```

Expected: `10 runs, 19 assertions, 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add lib/simple_a2a/models/part.rb lib/simple_a2a.rb test/models/test_part.rb
git commit -m "feat: add Models::Part with OneOf content and factories"
```

---

## Task 5: Models::Message

**Files:**
- Create: `lib/simple_a2a/models/message.rb`
- Create: `test/models/test_message.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_message.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestMessage < Minitest::Test
  def test_user_factory_with_string
    m = SimpleA2a::Models::Message.user("hello")
    assert_equal "user", m.role
    assert_equal 1, m.parts.length
    assert_equal "hello", m.parts[0].text
  end

  def test_agent_factory_with_parts
    part = SimpleA2a::Models::Part.json({ result: "ok" })
    m = SimpleA2a::Models::Message.agent(part)
    assert_equal "agent", m.role
    assert_equal part, m.parts[0]
  end

  def test_auto_generates_message_id
    m = SimpleA2a::Models::Message.user("hi")
    refute_nil m.message_id
    assert_match(/\A[0-9a-f-]{36}\z/, m.message_id)
  end

  def test_user_predicate
    m = SimpleA2a::Models::Message.user("hi")
    assert m.user?
    refute m.agent?
  end

  def test_valid_requires_role_and_parts
    m = SimpleA2a::Models::Message.new
    refute m.valid?
  end

  def test_valid_with_role_and_parts
    m = SimpleA2a::Models::Message.user("ok")
    assert m.valid?
  end

  def test_to_h_serializes_parts
    m = SimpleA2a::Models::Message.user("text content")
    h = m.to_h
    assert_equal "user", h["role"]
    assert_kind_of Array, h["parts"]
    assert_equal "text content", h["parts"][0]["text"]
    assert h.key?("messageId")
  end

  def test_from_hash_deserializes_parts
    hash = {
      "messageId" => "abc-123",
      "role"      => "user",
      "parts"     => [{ "text" => "hello", "mediaType" => "text/plain" }]
    }
    m = SimpleA2a::Models::Message.from_hash(hash)
    assert_equal "abc-123", m.message_id
    assert_equal "user", m.role
    assert_instance_of SimpleA2a::Models::Part, m.parts[0]
    assert_equal "hello", m.parts[0].text
  end

  def test_text_content_joins_text_parts
    m = SimpleA2a::Models::Message.user("hello", "world")
    assert_equal "hello\nworld", m.text_content
  end

  def test_round_trip
    m = SimpleA2a::Models::Message.user("round trip")
    restored = SimpleA2a::Models::Message.from_hash(JSON.parse(m.to_json))
    assert_equal m.message_id, restored.message_id
    assert_equal m.role, restored.role
    assert_equal m.parts[0].text, restored.parts[0].text
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/models/test_message.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models::Message`

- [ ] **Step 3: Create lib/simple_a2a/models/message.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class Message < Base
      attribute :message_id
      attribute :role,              required: true
      attribute :parts,             type: [Part], default: -> { [] }, required: true
      attribute :context_id
      attribute :task_id
      attribute :reference_task_ids, default: -> { [] }
      attribute :metadata
      attribute :extensions,        default: -> { [] }

      def self.user(*content)
        new(message_id: SecureRandom.uuid, role: Types::Role::USER, parts: build_parts(content))
      end

      def self.agent(*content)
        new(message_id: SecureRandom.uuid, role: Types::Role::AGENT, parts: build_parts(content))
      end

      def self.build_parts(content)
        content.map do |c|
          c.is_a?(Part) ? c : Part.text(c.to_s)
        end
      end
      private_class_method :build_parts

      def initialize(**kwargs)
        kwargs[:message_id] ||= SecureRandom.uuid
        super
      end

      def user?  = role == Types::Role::USER
      def agent? = role == Types::Role::AGENT

      def text_content
        parts.select(&:text?).map(&:text).join("\n")
      end

      def valid?
        !role.nil? && !parts.nil? && !parts.empty?
      end
    end
  end
end
```

- [ ] **Step 4: Add require to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/models/message"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_message.rb
```

Expected: `11 runs, 23 assertions, 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add lib/simple_a2a/models/message.rb lib/simple_a2a.rb test/models/test_message.rb
git commit -m "feat: add Models::Message with role, parts, and factories"
```

---

## Task 6: Models::Artifact

**Files:**
- Create: `lib/simple_a2a/models/artifact.rb`
- Create: `test/models/test_artifact.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_artifact.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestArtifact < Minitest::Test
  def test_auto_generates_artifact_id
    a = SimpleA2a::Models::Artifact.new(parts: [SimpleA2a::Models::Part.text("result")])
    refute_nil a.artifact_id
    assert_match(/\A[0-9a-f-]{36}\z/, a.artifact_id)
  end

  def test_valid_requires_at_least_one_part
    a = SimpleA2a::Models::Artifact.new(parts: [])
    refute a.valid?
  end

  def test_valid_with_part
    a = SimpleA2a::Models::Artifact.new(parts: [SimpleA2a::Models::Part.text("x")])
    assert a.valid?
  end

  def test_to_h_serializes_parts
    part = SimpleA2a::Models::Part.text("output")
    a = SimpleA2a::Models::Artifact.new(name: "report", parts: [part])
    h = a.to_h
    assert_equal "report", h["name"]
    assert_equal "output", h["parts"][0]["text"]
    assert h.key?("artifactId")
  end

  def test_from_hash
    hash = {
      "artifactId" => "art-1",
      "name"       => "result",
      "parts"      => [{ "text" => "done", "mediaType" => "text/plain" }]
    }
    a = SimpleA2a::Models::Artifact.from_hash(hash)
    assert_equal "art-1", a.artifact_id
    assert_equal "result", a.name
    assert_instance_of SimpleA2a::Models::Part, a.parts[0]
  end

  def test_round_trip
    original = SimpleA2a::Models::Artifact.new(
      name: "my-artifact",
      parts: [SimpleA2a::Models::Part.text("content")]
    )
    restored = SimpleA2a::Models::Artifact.from_hash(JSON.parse(original.to_json))
    assert_equal original.artifact_id, restored.artifact_id
    assert_equal original.name, restored.name
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/models/test_artifact.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models::Artifact`

- [ ] **Step 3: Create lib/simple_a2a/models/artifact.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class Artifact < Base
      attribute :artifact_id
      attribute :name
      attribute :description
      attribute :parts,      type: [Part], default: -> { [] }
      attribute :metadata
      attribute :extensions, default: -> { [] }

      def initialize(**kwargs)
        kwargs[:artifact_id] ||= SecureRandom.uuid
        super
      end

      def valid?
        !parts.nil? && !parts.empty?
      end
    end
  end
end
```

- [ ] **Step 4: Add require to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/models/artifact"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_artifact.rb
```

Expected: `6 runs, 14 assertions, 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add lib/simple_a2a/models/artifact.rb lib/simple_a2a.rb test/models/test_artifact.rb
git commit -m "feat: add Models::Artifact"
```

---

## Task 7: Models::TaskStatus and Models::Task

**Files:**
- Create: `lib/simple_a2a/models/task_status.rb`
- Create: `lib/simple_a2a/models/task.rb`
- Create: `test/models/test_task.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_task.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestTaskStatus < Minitest::Test
  def test_state_predicates
    ts = SimpleA2a::Models::TaskStatus.new(state: "completed")
    assert ts.terminal?
    refute ts.interrupted?
    refute ts.active?
  end

  def test_interrupted_predicate
    ts = SimpleA2a::Models::TaskStatus.new(state: "input_required")
    assert ts.interrupted?
    refute ts.terminal?
  end

  def test_auto_sets_timestamp
    ts = SimpleA2a::Models::TaskStatus.new(state: "working")
    refute_nil ts.timestamp
  end

  def test_from_hash
    ts = SimpleA2a::Models::TaskStatus.from_hash({ "state" => "completed", "timestamp" => "2026-05-08T10:00:00Z" })
    assert_equal "completed", ts.state
    assert_equal "2026-05-08T10:00:00Z", ts.timestamp
  end
end

class TestTask < Minitest::Test
  T = SimpleA2a::Models::Types::TaskState

  def submitted_task
    SimpleA2a::Models::Task.new(
      status: SimpleA2a::Models::TaskStatus.new(state: T::SUBMITTED)
    )
  end

  def test_auto_generates_id
    t = submitted_task
    refute_nil t.id
    assert_match(/\A[0-9a-f-]{36}\z/, t.id)
  end

  def test_auto_generates_context_id
    t = submitted_task
    refute_nil t.context_id
  end

  def test_state_delegation
    t = submitted_task
    assert_equal T::SUBMITTED, t.state
    refute t.terminal?
    refute t.interrupted?
  end

  def test_start_transition
    t = submitted_task
    t.start!
    assert_equal T::WORKING, t.state
  end

  def test_complete_transition
    t = submitted_task
    artifact = SimpleA2a::Models::Artifact.new(parts: [SimpleA2a::Models::Part.text("done")])
    t.complete!(artifacts: [artifact])
    assert_equal T::COMPLETED, t.state
    assert_equal [artifact], t.artifacts
    assert t.terminal?
  end

  def test_fail_transition
    t = submitted_task
    msg = SimpleA2a::Models::Message.agent("error occurred")
    t.fail!(message: msg)
    assert_equal T::FAILED, t.state
    assert t.terminal?
  end

  def test_cancel_transition
    t = submitted_task
    t.cancel!
    assert_equal T::CANCELED, t.state
  end

  def test_reject_transition
    t = submitted_task
    t.reject!
    assert_equal T::REJECTED, t.state
  end

  def test_require_input_transition
    t = submitted_task
    t.require_input!(message: SimpleA2a::Models::Message.agent("need more info"))
    assert_equal T::INPUT_REQUIRED, t.state
    assert t.interrupted?
  end

  def test_to_h_serializes_status
    t = submitted_task
    h = t.to_h
    assert_equal T::SUBMITTED, h["status"]["state"]
    assert h.key?("id")
    assert h.key?("contextId")
  end

  def test_from_hash
    hash = {
      "id"        => "task-1",
      "contextId" => "ctx-1",
      "status"    => { "state" => "working", "timestamp" => "2026-05-08T00:00:00Z" }
    }
    t = SimpleA2a::Models::Task.from_hash(hash)
    assert_equal "task-1", t.id
    assert_equal "working", t.state
    assert_instance_of SimpleA2a::Models::TaskStatus, t.status
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
mkdir -p test/models
bundle exec ruby -Ilib -Itest test/models/test_task.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models::TaskStatus`

- [ ] **Step 3: Create lib/simple_a2a/models/task_status.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class TaskStatus < Base
      attribute :state,     required: true
      attribute :message,   type: Message
      attribute :timestamp

      def initialize(**kwargs)
        kwargs[:timestamp] ||= Time.now.iso8601
        super
      end

      def terminal?    = Types::TaskState.terminal?(state)
      def interrupted? = Types::TaskState.interrupted?(state)
      def active?      = Types::TaskState.active?(state)
    end
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/models/task.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class Task < Base
      attribute :id
      attribute :context_id
      attribute :status,    type: TaskStatus, required: true
      attribute :artifacts, type: [Artifact], default: -> { [] }
      attribute :history,   type: [Message],  default: -> { [] }
      attribute :metadata

      def initialize(**kwargs)
        kwargs[:id]         ||= SecureRandom.uuid
        kwargs[:context_id] ||= SecureRandom.uuid
        super
      end

      def state        = status&.state
      def terminal?    = status&.terminal?   || false
      def interrupted? = status&.interrupted? || false

      def start!
        transition!(Types::TaskState::WORKING)
      end

      def complete!(artifacts: [])
        self.artifacts = artifacts unless artifacts.empty?
        transition!(Types::TaskState::COMPLETED)
      end

      def fail!(message: nil)
        transition!(Types::TaskState::FAILED, message: message)
      end

      def cancel!
        transition!(Types::TaskState::CANCELED)
      end

      def reject!(message: nil)
        transition!(Types::TaskState::REJECTED, message: message)
      end

      def require_input!(message: nil)
        transition!(Types::TaskState::INPUT_REQUIRED, message: message)
      end

      def require_auth!(message: nil)
        transition!(Types::TaskState::AUTH_REQUIRED, message: message)
      end

      private

      def transition!(new_state, message: nil)
        self.status = TaskStatus.new(state: new_state, message: message)
      end
    end
  end
end
```

- [ ] **Step 5: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/models/task_status"
require_relative "simple_a2a/models/task"
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_task.rb
```

Expected: `15 runs, 32 assertions, 0 failures, 0 errors`

- [ ] **Step 7: Commit**

```bash
git add lib/simple_a2a/models/task_status.rb lib/simple_a2a/models/task.rb lib/simple_a2a.rb test/models/test_task.rb
git commit -m "feat: add Models::TaskStatus and Models::Task with state transitions"
```

---

## Task 8: Models::StreamResponse, SendMessageConfig, PushNotification

**Files:**
- Create: `lib/simple_a2a/models/stream_response.rb`
- Create: `lib/simple_a2a/models/send_message_config.rb`
- Create: `lib/simple_a2a/models/push_notification.rb`
- Create: `test/models/test_stream_response.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_stream_response.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestStreamResponse < Minitest::Test
  def test_task_wrapper
    task = SimpleA2a::Models::Task.new(
      status: SimpleA2a::Models::TaskStatus.new(state: "submitted")
    )
    sr = SimpleA2a::Models::StreamResponse.new(task: task)
    assert sr.task?
    refute sr.message?
    refute sr.status_update?
    refute sr.artifact_update?
    assert_equal task, sr.task
  end

  def test_message_wrapper
    msg = SimpleA2a::Models::Message.user("hello")
    sr = SimpleA2a::Models::StreamResponse.new(message: msg)
    assert sr.message?
    refute sr.task?
  end
end

class TestSendMessageConfig < Minitest::Test
  def test_defaults
    cfg = SimpleA2a::Models::SendMessageConfiguration.new
    assert_equal [], cfg.accepted_output_modes
    assert_equal false, cfg.return_immediately
  end

  def test_from_hash
    cfg = SimpleA2a::Models::SendMessageConfiguration.from_hash({
      "returnImmediately" => true,
      "historyLength"     => 5
    })
    assert cfg.return_immediately
    assert_equal 5, cfg.history_length
  end
end

class TestPushNotificationConfig < Minitest::Test
  def test_from_hash
    cfg = SimpleA2a::Models::PushNotificationConfig.from_hash({
      "id"         => "cfg-1",
      "taskId"     => "task-1",
      "webhookUrl" => "https://example.com/hook"
    })
    assert_equal "cfg-1",  cfg.id
    assert_equal "task-1", cfg.task_id
    assert_equal "https://example.com/hook", cfg.webhook_url
  end

  def test_valid_requires_webhook_url
    cfg = SimpleA2a::Models::PushNotificationConfig.new
    refute cfg.valid?
    cfg.webhook_url = "https://example.com/hook"
    assert cfg.valid?
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/models/test_stream_response.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models::StreamResponse`

- [ ] **Step 3: Create lib/simple_a2a/models/stream_response.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class StreamResponse < Base
      attribute :task
      attribute :message
      attribute :status_update
      attribute :artifact_update

      def task?           = !task.nil?
      def message?        = !message.nil?
      def status_update?  = !status_update.nil?
      def artifact_update? = !artifact_update.nil?

      def self.from_hash(hash)
        return nil if hash.nil?
        if hash["task"]
          new(task: Task.from_hash(hash["task"]))
        elsif hash["message"]
          new(message: Message.from_hash(hash["message"]))
        elsif hash["statusUpdate"]
          new(status_update: hash["statusUpdate"])
        elsif hash["artifactUpdate"]
          new(artifact_update: hash["artifactUpdate"])
        else
          new
        end
      end
    end
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/models/send_message_config.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class SendMessageConfiguration < Base
      attribute :accepted_output_modes,       default: -> { [] }
      attribute :task_push_notification_config, type: nil
      attribute :history_length
      attribute :return_immediately,          default: false
    end
  end
end
```

- [ ] **Step 5: Create lib/simple_a2a/models/push_notification.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class AuthenticationInfo < Base
      attribute :scheme,      required: true
      attribute :value,       required: true
      attribute :header_name
    end

    class PushNotificationConfig < Base
      attribute :id
      attribute :task_id
      attribute :webhook_url,         required: true
      attribute :authentication_info, type: AuthenticationInfo
      attribute :event_types,         default: -> { [] }

      def valid?
        !webhook_url.nil? && !webhook_url.empty?
      end
    end
  end
end
```

- [ ] **Step 6: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/models/stream_response"
require_relative "simple_a2a/models/send_message_config"
require_relative "simple_a2a/models/push_notification"
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_stream_response.rb
```

Expected: `7 runs, 13 assertions, 0 failures, 0 errors`

- [ ] **Step 8: Commit**

```bash
git add lib/simple_a2a/models/stream_response.rb lib/simple_a2a/models/send_message_config.rb lib/simple_a2a/models/push_notification.rb lib/simple_a2a.rb test/models/test_stream_response.rb
git commit -m "feat: add StreamResponse, SendMessageConfiguration, PushNotificationConfig"
```

---

## Task 9: Models::AgentCard cluster and SecurityScheme

**Files:**
- Create: `lib/simple_a2a/models/agent_card.rb`
- Create: `lib/simple_a2a/models/security_scheme.rb`
- Create: `test/models/test_agent_card.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/test_agent_card.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestAgentCard < Minitest::Test
  M = SimpleA2a::Models

  def minimal_card
    M::AgentCard.new(
      name:         "test-agent",
      version:      "1.0.0",
      capabilities: M::AgentCapabilities.new,
      skills:       [M::AgentSkill.new(name: "answer")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost:8000", version: "1.0")]
    )
  end

  def test_valid_card
    assert minimal_card.valid?
  end

  def test_invalid_without_name
    card = minimal_card
    card.name = nil
    refute card.valid?
  end

  def test_capabilities_defaults
    caps = M::AgentCapabilities.new
    refute caps.streaming
    refute caps.push_notifications
    refute caps.extended_agent_card
  end

  def test_to_h_serializes_nested
    card = minimal_card
    h = card.to_h
    assert_equal "test-agent", h["name"]
    assert_equal "1.0.0", h["version"]
    assert_kind_of Hash, h["capabilities"]
    assert_kind_of Array, h["skills"]
    assert_equal "answer", h["skills"][0]["name"]
  end

  def test_from_hash_round_trip
    card = minimal_card
    restored = M::AgentCard.from_hash(JSON.parse(card.to_json))
    assert_equal card.name, restored.name
    assert_equal card.version, restored.version
    assert_instance_of M::AgentCapabilities, restored.capabilities
    assert_equal 1, restored.skills.length
    assert_equal "answer", restored.skills[0].name
  end

  def test_provider_optional
    card = minimal_card
    card.provider = M::AgentProvider.new(name: "Acme Corp", url: "https://acme.com")
    h = card.to_h
    assert_equal "Acme Corp", h["provider"]["name"]
  end
end

class TestSecurityScheme < Minitest::Test
  def test_api_key_from_hash
    scheme = SimpleA2a::Models::SecurityScheme.from_hash({
      "type"       => "apiKey",
      "apiKeyName" => "X-API-Key",
      "in"         => "header"
    })
    assert_instance_of SimpleA2a::Models::APIKeySecurityScheme, scheme
    assert_equal "X-API-Key", scheme.api_key_name
  end

  def test_http_auth_from_hash
    scheme = SimpleA2a::Models::SecurityScheme.from_hash({
      "type"   => "http",
      "scheme" => "bearer"
    })
    assert_instance_of SimpleA2a::Models::HTTPAuthSecurityScheme, scheme
    assert_equal "bearer", scheme.scheme
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/models/test_agent_card.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Models::AgentCard`

- [ ] **Step 3: Create lib/simple_a2a/models/agent_card.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class AgentProvider < Base
      attribute :name, required: true
      attribute :url
      attribute :description
    end

    class AgentCapabilities < Base
      attribute :streaming,           default: false
      attribute :push_notifications,  default: false
      attribute :extended_agent_card, default: false
    end

    class AgentSkill < Base
      attribute :name,         required: true
      attribute :description
      attribute :input_schema
      attribute :output_schema
    end

    class AgentInterface < Base
      attribute :type,    required: true
      attribute :url,     required: true
      attribute :version, required: true
    end

    class AgentCard < Base
      attribute :name,            required: true
      attribute :description
      attribute :version,         required: true
      attribute :provider,        type: AgentProvider
      attribute :capabilities,    type: AgentCapabilities, required: true
      attribute :skills,          type: [AgentSkill],      default: -> { [] }, required: true
      attribute :interfaces,      type: [AgentInterface],  default: -> { [] }, required: true
      attribute :security_schemes, default: -> { [] }
      attribute :security,        default: -> { [] }
      attribute :extensions,      default: -> { [] }

      def valid?
        !name.nil? && !version.nil? && !capabilities.nil? &&
          !skills.nil? && !interfaces.nil?
      end
    end
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/models/security_scheme.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Models
    class SecurityScheme < Base
      attribute :type

      def self.from_hash(hash)
        return nil if hash.nil?
        klass = case hash["type"]
                when "apiKey"      then APIKeySecurityScheme
                when "http"        then HTTPAuthSecurityScheme
                when "oauth2"      then OAuth2SecurityScheme
                when "openIdConnect" then OpenIdConnectSecurityScheme
                when "mutualTLS"   then MutualTlsSecurityScheme
                else SecurityScheme
                end
        klass.superclass == SecurityScheme ? klass.new(**symbolize(hash)) : super
      end

      private_class_method def self.symbolize(hash)
        hash.transform_keys { |k| k.gsub(/([A-Z])/) { "_#{$1.downcase}" }.to_sym }
      end
    end

    class APIKeySecurityScheme < SecurityScheme
      attribute :api_key_name
      attribute :in
      attribute :description
    end

    class HTTPAuthSecurityScheme < SecurityScheme
      attribute :scheme
      attribute :description
    end

    class OAuth2SecurityScheme < SecurityScheme
      attribute :flows
      attribute :description
    end

    class OpenIdConnectSecurityScheme < SecurityScheme
      attribute :open_id_connect_url
      attribute :description
    end

    class MutualTlsSecurityScheme < SecurityScheme
      attribute :description
    end
  end
end
```

- [ ] **Step 5: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/models/agent_card"
require_relative "simple_a2a/models/security_scheme"
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/models/test_agent_card.rb
```

Expected: `8 runs, 19 assertions, 0 failures, 0 errors`

- [ ] **Step 7: Commit**

```bash
git add lib/simple_a2a/models/agent_card.rb lib/simple_a2a/models/security_scheme.rb lib/simple_a2a.rb test/models/test_agent_card.rb
git commit -m "feat: add AgentCard cluster and polymorphic SecurityScheme"
```

---

## Task 10: Events

**Files:**
- Create: `lib/simple_a2a/events/task_status_update.rb`
- Create: `lib/simple_a2a/events/task_artifact_update.rb`
- Create: `test/events/test_events.rb`

- [ ] **Step 1: Write failing test**

Create `test/events/test_events.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestEvents < Minitest::Test
  M = SimpleA2a::Models
  E = SimpleA2a::Events

  def test_status_update_sse_format
    status = M::TaskStatus.new(state: "working")
    event = E::TaskStatusUpdateEvent.new(
      task_id: "t-1", context_id: "c-1", status: status
    )
    sse = event.sse_format(jsonrpc_id: "req-1")
    assert sse.start_with?("data: ")
    assert sse.end_with?("\n\n")
    parsed = JSON.parse(sse.sub("data: ", "").strip)
    assert_equal "2.0", parsed["jsonrpc"]
    assert_equal "req-1", parsed["id"]
    assert_equal "working", parsed["result"]["status"]["state"]
  end

  def test_artifact_update_sse_format
    artifact = M::Artifact.new(parts: [M::Part.text("chunk")])
    event = E::TaskArtifactUpdateEvent.new(
      task_id: "t-1", context_id: "c-1", artifact: artifact, last_chunk: true
    )
    sse = event.sse_format(jsonrpc_id: "req-1")
    parsed = JSON.parse(sse.sub("data: ", "").strip)
    assert parsed["result"]["artifact"]["parts"][0]["text"] == "chunk"
    assert parsed["result"]["lastChunk"]
  end

  def test_status_update_from_hash
    hash = {
      "taskId"    => "t-1",
      "contextId" => "c-1",
      "status"    => { "state" => "completed", "timestamp" => "2026-05-08T00:00:00Z" }
    }
    event = E::TaskStatusUpdateEvent.from_hash(hash)
    assert_equal "t-1", event.task_id
    assert_instance_of M::TaskStatus, event.status
    assert_equal "completed", event.status.state
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
mkdir -p test/events
bundle exec ruby -Ilib -Itest test/events/test_events.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Events`

- [ ] **Step 3: Create lib/simple_a2a/events/task_status_update.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Events
    class TaskStatusUpdateEvent < Models::Base
      attribute :task_id,    required: true
      attribute :context_id, required: true
      attribute :status,     type: Models::TaskStatus, required: true
      attribute :metadata

      def sse_format(jsonrpc_id: nil)
        payload = {
          "jsonrpc" => "2.0",
          "id"      => jsonrpc_id,
          "result"  => {
            "taskId"    => task_id,
            "contextId" => context_id,
            "status"    => status.to_h
          }
        }
        "data: #{JSON.generate(payload)}\n\n"
      end
    end
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/events/task_artifact_update.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Events
    class TaskArtifactUpdateEvent < Models::Base
      attribute :task_id,    required: true
      attribute :context_id, required: true
      attribute :artifact,   type: Models::Artifact, required: true
      attribute :append,     default: false
      attribute :last_chunk, default: false
      attribute :metadata

      def sse_format(jsonrpc_id: nil)
        payload = {
          "jsonrpc" => "2.0",
          "id"      => jsonrpc_id,
          "result"  => {
            "taskId"    => task_id,
            "contextId" => context_id,
            "artifact"  => artifact.to_h,
            "append"    => append,
            "lastChunk" => last_chunk
          }
        }
        "data: #{JSON.generate(payload)}\n\n"
      end
    end
  end
end
```

- [ ] **Step 5: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/events/task_status_update"
require_relative "simple_a2a/events/task_artifact_update"
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/events/test_events.rb
```

Expected: `3 runs, 10 assertions, 0 failures, 0 errors`

- [ ] **Step 7: Commit**

```bash
git add lib/simple_a2a/events/ lib/simple_a2a.rb test/events/test_events.rb
git commit -m "feat: add TaskStatusUpdateEvent and TaskArtifactUpdateEvent with SSE format"
```

---

## Task 11: JSON-RPC 2.0 Layer

**Files:**
- Create: `lib/simple_a2a/jsonrpc/error.rb`
- Create: `lib/simple_a2a/jsonrpc/request.rb`
- Create: `lib/simple_a2a/jsonrpc/response.rb`
- Create: `test/jsonrpc/test_jsonrpc.rb`

- [ ] **Step 1: Write failing test**

Create `test/jsonrpc/test_jsonrpc.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestJSONRPCRequest < Minitest::Test
  def test_parse_send_message
    body = JSON.generate({
      "jsonrpc"     => "2.0",
      "method"      => "SendMessage",
      "params"      => { "message" => { "role" => "user", "parts" => [] } },
      "id"          => "req-1",
      "a2a-version" => "1.0"
    })
    req = SimpleA2a::JSONRPC::Request.parse(body)
    assert_equal "2.0",          req.jsonrpc
    assert_equal "SendMessage",  req.method
    assert_equal "req-1",        req.id
    assert_equal "1.0",          req.a2a_version
    assert_kind_of Hash,         req.params
  end

  def test_parse_invalid_json_raises
    assert_raises(SimpleA2a::JSONRPC::ParseError) do
      SimpleA2a::JSONRPC::Request.parse("{not json}")
    end
  end

  def test_parse_missing_method_raises
    body = JSON.generate({ "jsonrpc" => "2.0", "id" => "1" })
    assert_raises(SimpleA2a::JSONRPC::InvalidRequestError) do
      SimpleA2a::JSONRPC::Request.parse(body)
    end
  end

  def test_version_defaults_to_03_when_absent
    body = JSON.generate({ "jsonrpc" => "2.0", "method" => "GetTask", "id" => "1" })
    req = SimpleA2a::JSONRPC::Request.parse(body)
    assert_equal "0.3", req.a2a_version
  end
end

class TestJSONRPCResponse < Minitest::Test
  def test_success_format
    r = SimpleA2a::JSONRPC::Response.success(id: "req-1", result: { "foo" => "bar" })
    h = r.to_h
    assert_equal "2.0",          h["jsonrpc"]
    assert_equal "req-1",        h["id"]
    assert_equal "bar",          h["result"]["foo"]
    refute h.key?("error")
  end

  def test_error_format
    r = SimpleA2a::JSONRPC::Response.error(
      id:   "req-1",
      code: SimpleA2a::JSONRPC::ErrorCodes::TASK_NOT_FOUND,
      message: "Task not found"
    )
    h = r.to_h
    assert_equal "2.0",   h["jsonrpc"]
    assert_equal -32001,  h["error"]["code"]
    assert_equal "Task not found", h["error"]["message"]
    refute h.key?("result")
  end

  def test_to_json
    r = SimpleA2a::JSONRPC::Response.success(id: "1", result: {})
    parsed = JSON.parse(r.to_json)
    assert_equal "2.0", parsed["jsonrpc"]
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
mkdir -p test/jsonrpc
bundle exec ruby -Ilib -Itest test/jsonrpc/test_jsonrpc.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::JSONRPC`

- [ ] **Step 3: Create lib/simple_a2a/jsonrpc/error.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module JSONRPC
    module ErrorCodes
      PARSE_ERROR             = -32700
      INVALID_REQUEST         = -32600
      METHOD_NOT_FOUND        = -32601
      INVALID_PARAMS          = -32602
      INTERNAL_ERROR          = -32603
      TASK_NOT_FOUND          = -32001
      TASK_NOT_CANCELABLE     = -32002
      PUSH_NOT_SUPPORTED      = -32003
      UNSUPPORTED_OPERATION   = -32004
      CONTENT_TYPE_NOT_SUPPORTED = -32005
      INVALID_AGENT_RESPONSE  = -32006
      EXTENSION_REQUIRED      = -32007
      VERSION_NOT_SUPPORTED   = -32008
    end

    ParseError        = Class.new(SimpleA2a::Error)
    InvalidRequestError = Class.new(SimpleA2a::Error)
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/jsonrpc/request.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module JSONRPC
    class Request
      attr_reader :jsonrpc, :method, :params, :id, :a2a_version, :a2a_extensions

      def initialize(jsonrpc:, method:, params:, id:, a2a_version:, a2a_extensions: nil)
        @jsonrpc         = jsonrpc
        @method          = method
        @params          = params
        @id              = id
        @a2a_version     = a2a_version
        @a2a_extensions  = a2a_extensions
      end

      def self.parse(body)
        data = JSON.parse(body)
        raise ParseError, "Invalid JSON" unless data.is_a?(Hash)
        raise InvalidRequestError, "Missing method" unless data["method"]
        new(
          jsonrpc:        data["jsonrpc"] || "2.0",
          method:         data["method"],
          params:         data["params"] || {},
          id:             data["id"],
          a2a_version:    data["a2a-version"] || "0.3",
          a2a_extensions: data["a2a-extensions"]
        )
      rescue JSON::ParserError => e
        raise ParseError, e.message
      end
    end
  end
end
```

- [ ] **Step 5: Create lib/simple_a2a/jsonrpc/response.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module JSONRPC
    class Response
      def self.success(id:, result:)
        new(id: id, result: result)
      end

      def self.error(id:, code:, message:, data: nil)
        new(id: id, error: { "code" => code, "message" => message, "data" => data }.compact)
      end

      def initialize(id:, result: nil, error: nil)
        @id     = id
        @result = result
        @error  = error
      end

      def to_h
        h = { "jsonrpc" => "2.0", "id" => @id }
        h["result"] = @result unless @result.nil?
        h["error"]  = @error  unless @error.nil?
        h
      end

      def to_json(*)
        JSON.generate(to_h)
      end
    end
  end
end
```

- [ ] **Step 6: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/jsonrpc/error"
require_relative "simple_a2a/jsonrpc/request"
require_relative "simple_a2a/jsonrpc/response"
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/jsonrpc/test_jsonrpc.rb
```

Expected: `7 runs, 18 assertions, 0 failures, 0 errors`

- [ ] **Step 8: Commit**

```bash
git add lib/simple_a2a/jsonrpc/ lib/simple_a2a.rb test/jsonrpc/test_jsonrpc.rb
git commit -m "feat: add JSON-RPC 2.0 request parser, response builder, and error codes"
```

---

## Task 12: Storage::Base and Storage::Memory

**Files:**
- Create: `lib/simple_a2a/storage/base.rb`
- Create: `lib/simple_a2a/storage/memory.rb`
- Create: `test/storage/test_memory.rb`

- [ ] **Step 1: Write failing test**

Create `test/storage/test_memory.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestMemoryStorage < Minitest::Test
  M = SimpleA2a::Models

  def setup
    @storage = SimpleA2a::Storage::Memory.new
    @task = M::Task.new(status: M::TaskStatus.new(state: "submitted"))
  end

  def test_save_and_get_task
    @storage.save_task(@task)
    found = @storage.get_task(@task.id)
    assert_equal @task.id, found.id
  end

  def test_get_task_returns_nil_for_unknown
    assert_nil @storage.get_task("nonexistent-id")
  end

  def test_list_tasks_empty
    result = @storage.list_tasks
    assert_equal [], result[:tasks]
    assert_equal 0, result[:total_size]
  end

  def test_list_tasks_returns_saved
    @storage.save_task(@task)
    result = @storage.list_tasks
    assert_equal 1, result[:tasks].length
    assert_equal @task.id, result[:tasks][0].id
  end

  def test_list_tasks_filter_by_context_id
    other = M::Task.new(status: M::TaskStatus.new(state: "working"))
    @storage.save_task(@task)
    @storage.save_task(other)

    result = @storage.list_tasks(context_id: @task.context_id)
    assert_equal 1, result[:tasks].length
    assert_equal @task.id, result[:tasks][0].id
  end

  def test_list_tasks_filter_by_status
    @task.start!
    @storage.save_task(@task)
    other = M::Task.new(status: M::TaskStatus.new(state: "submitted"))
    @storage.save_task(other)

    result = @storage.list_tasks(status: "working")
    assert_equal 1, result[:tasks].length
    assert_equal @task.id, result[:tasks][0].id
  end

  def test_list_tasks_pagination
    5.times { @storage.save_task(M::Task.new(status: M::TaskStatus.new(state: "submitted"))) }
    result = @storage.list_tasks(page_size: 2)
    assert_equal 2, result[:tasks].length
    assert_equal 5, result[:total_size]
    refute_nil result[:next_page_token]
  end

  def test_create_and_get_push_config
    config = M::PushNotificationConfig.new(
      id: "cfg-1", task_id: @task.id, webhook_url: "https://example.com/hook"
    )
    @storage.create_push_config(config)
    found = @storage.get_push_config(@task.id, "cfg-1")
    assert_equal "cfg-1", found.id
    assert_equal "https://example.com/hook", found.webhook_url
  end

  def test_delete_push_config
    config = M::PushNotificationConfig.new(
      id: "cfg-1", task_id: @task.id, webhook_url: "https://example.com/hook"
    )
    @storage.create_push_config(config)
    assert @storage.delete_push_config(@task.id, "cfg-1")
    assert_nil @storage.get_push_config(@task.id, "cfg-1")
  end

  def test_list_push_configs
    2.times do |i|
      @storage.create_push_config(M::PushNotificationConfig.new(
        id: "cfg-#{i}", task_id: @task.id, webhook_url: "https://example.com/#{i}"
      ))
    end
    result = @storage.list_push_configs(@task.id)
    assert_equal 2, result[:configs].length
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
mkdir -p test/storage
bundle exec ruby -Ilib -Itest test/storage/test_memory.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Storage`

- [ ] **Step 3: Create lib/simple_a2a/storage/base.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Storage
    class Base
      def get_task(id)                       = raise NotImplementedError
      def save_task(task)                    = raise NotImplementedError
      def list_tasks(**filters)              = raise NotImplementedError
      def create_push_config(config)         = raise NotImplementedError
      def get_push_config(task_id, id)       = raise NotImplementedError
      def list_push_configs(task_id, **opts) = raise NotImplementedError
      def delete_push_config(task_id, id)    = raise NotImplementedError
      def close                              = nil
    end
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/storage/memory.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Storage
    class Memory < Base
      def initialize
        @tasks        = {}
        @push_configs = {}  # { task_id => { config_id => config } }
        @mutex        = Mutex.new
      end

      def get_task(id)
        @tasks[id]
      end

      def save_task(task)
        @mutex.synchronize { @tasks[task.id] = task }
        task
      end

      def list_tasks(context_id: nil, status: nil, page_size: 50, page_token: nil,
                     status_timestamp_after: nil, include_artifacts: true)
        all = @tasks.values
        all = all.select { |t| t.context_id == context_id } if context_id
        all = all.select { |t| t.state == status }          if status

        total = all.length
        offset = page_token ? page_token.to_i : 0
        page   = all[offset, page_size] || []
        next_token = (offset + page_size < total) ? (offset + page_size).to_s : nil

        unless include_artifacts
          page = page.map { |t| t_copy = t.dup; t_copy.artifacts = []; t_copy }
        end

        { tasks: page, next_page_token: next_token, total_size: total }
      end

      def create_push_config(config)
        @mutex.synchronize do
          @push_configs[config.task_id] ||= {}
          @push_configs[config.task_id][config.id] = config
        end
        config
      end

      def get_push_config(task_id, config_id)
        @push_configs.dig(task_id, config_id)
      end

      def list_push_configs(task_id, page_size: 50, page_token: nil)
        all = (@push_configs[task_id] || {}).values
        offset = page_token ? page_token.to_i : 0
        page   = all[offset, page_size] || []
        next_token = (offset + page_size < all.length) ? (offset + page_size).to_s : nil
        { configs: page, next_page_token: next_token }
      end

      def delete_push_config(task_id, config_id)
        @mutex.synchronize do
          return false unless @push_configs.dig(task_id, config_id)
          @push_configs[task_id].delete(config_id)
          true
        end
      end

      def clear!
        @mutex.synchronize { @tasks.clear; @push_configs.clear }
      end
    end
  end
end
```

- [ ] **Step 5: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/storage/base"
require_relative "simple_a2a/storage/memory"
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/storage/test_memory.rb
```

Expected: `11 runs, 22 assertions, 0 failures, 0 errors`

- [ ] **Step 7: Commit**

```bash
git add lib/simple_a2a/storage/ lib/simple_a2a.rb test/storage/test_memory.rb
git commit -m "feat: add Storage::Base interface and Storage::Memory implementation"
```

---

## Task 13: Server::AgentExecutor and Server::Context

**Files:**
- Create: `lib/simple_a2a/server/agent_executor.rb`
- Create: `lib/simple_a2a/server/context.rb`
- Create: `test/server/test_context.rb`

- [ ] **Step 1: Write failing test**

Create `test/server/test_context.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestAgentExecutor < Minitest::Test
  def test_execute_raises_not_implemented
    executor = SimpleA2a::Server::AgentExecutor.new
    assert_raises(NotImplementedError) { executor.execute(nil) }
  end

  def test_cancel_is_a_noop_by_default
    executor = SimpleA2a::Server::AgentExecutor.new
    assert_nil executor.cancel(nil)
  end
end

class TestContext < Minitest::Test
  M = SimpleA2a::Models

  def setup
    @task    = M::Task.new(status: M::TaskStatus.new(state: "submitted"))
    @message = M::Message.user("test input")
    @storage = SimpleA2a::Storage::Memory.new
    @storage.save_task(@task)
    @events  = []
    @ctx     = SimpleA2a::Server::Context.new(
      task:    @task,
      message: @message,
      storage: @storage,
      on_event: ->(event) { @events << event }
    )
  end

  def test_task_id_delegates
    assert_equal @task.id, @ctx.task_id
  end

  def test_context_id_delegates
    assert_equal @task.context_id, @ctx.context_id
  end

  def test_emit_status_publishes_event_and_updates_task
    @ctx.emit_status("working")
    assert_equal 1, @events.length
    assert_instance_of SimpleA2a::Events::TaskStatusUpdateEvent, @events[0]
    assert_equal "working", @task.state
  end

  def test_emit_artifact_publishes_event
    artifact = M::Artifact.new(parts: [M::Part.text("output")])
    @ctx.emit_artifact(artifact)
    assert_equal 1, @events.length
    assert_instance_of SimpleA2a::Events::TaskArtifactUpdateEvent, @events[0]
  end

  def test_cancel_flag
    refute @ctx.cancel?
    @ctx.cancel!
    assert @ctx.cancel?
  end

  def test_require_input_transitions_task
    @ctx.require_input!(message: M::Message.agent("need more info"))
    assert_equal "input_required", @task.state
    assert_equal 1, @events.length
  end
end

class TestResumeContext < Minitest::Test
  M = SimpleA2a::Models

  def test_resume_message_exposed
    task    = M::Task.new(status: M::TaskStatus.new(state: "input_required"))
    storage = SimpleA2a::Storage::Memory.new
    storage.save_task(task)
    resume_msg = M::Message.user("here is the info")

    ctx = SimpleA2a::Server::ResumeContext.new(
      task:           task,
      message:        resume_msg,
      storage:        storage,
      on_event:       ->(_e) {},
      resume_message: resume_msg
    )
    assert_equal resume_msg, ctx.resume_message
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
mkdir -p test/server
bundle exec ruby -Ilib -Itest test/server/test_context.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Server`

- [ ] **Step 3: Create lib/simple_a2a/server/agent_executor.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Server
    class AgentExecutor
      def execute(context)
        raise NotImplementedError, "#{self.class}#execute must be implemented"
      end

      def cancel(context)
        nil
      end
    end
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/server/context.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Server
    class Context
      attr_reader :task, :message, :configuration, :storage

      def initialize(task:, message:, storage:, on_event:, configuration: nil)
        @task          = task
        @message       = message
        @storage       = storage
        @on_event      = on_event
        @configuration = configuration
        @canceled      = false
      end

      def task_id    = @task.id
      def context_id = @task.context_id

      def emit_status(state, message: nil)
        @task.send(:transition!, state, message: message)
        @storage.save_task(@task)
        event = Events::TaskStatusUpdateEvent.new(
          task_id:    @task.id,
          context_id: @task.context_id,
          status:     @task.status
        )
        @on_event.call(event)
      end

      def emit_artifact(artifact, append: false, last_chunk: true)
        @task.artifacts ||= []
        @task.artifacts << artifact
        @storage.save_task(@task)
        event = Events::TaskArtifactUpdateEvent.new(
          task_id:    @task.id,
          context_id: @task.context_id,
          artifact:   artifact,
          append:     append,
          last_chunk: last_chunk
        )
        @on_event.call(event)
      end

      def require_input!(message: nil)
        emit_status(Models::Types::TaskState::INPUT_REQUIRED, message: message)
      end

      def require_auth!(message: nil)
        emit_status(Models::Types::TaskState::AUTH_REQUIRED, message: message)
      end

      def cancel!
        @canceled = true
      end

      def cancel?
        @canceled
      end

      def log(msg)
        SimpleA2a.logger&.info(msg)
      end
    end

    class ResumeContext < Context
      attr_reader :resume_message

      def initialize(resume_message:, **kwargs)
        super(**kwargs)
        @resume_message = resume_message
      end
    end
  end
end
```

- [ ] **Step 5: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/server/agent_executor"
require_relative "simple_a2a/server/context"
```

- [ ] **Step 6: Fix access to private transition! method in Context**

In `lib/simple_a2a/models/task.rb`, change `private` before `transition!` to allow internal use from Context. Add a public `transition!` method:

```ruby
# In lib/simple_a2a/models/task.rb, replace the private section:

def transition!(new_state, message: nil)
  self.status = TaskStatus.new(state: new_state, message: message)
end
```

Remove the `private` declaration — `transition!` remains public since Context calls it directly.

- [ ] **Step 7: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/server/test_context.rb
```

Expected: `8 runs, 14 assertions, 0 failures, 0 errors`

- [ ] **Step 8: Commit**

```bash
git add lib/simple_a2a/server/agent_executor.rb lib/simple_a2a/server/context.rb lib/simple_a2a/models/task.rb lib/simple_a2a.rb test/server/test_context.rb
git commit -m "feat: add Server::AgentExecutor, Context, and ResumeContext"
```

---

## Task 14: Server::EventRouter

**Files:**
- Create: `lib/simple_a2a/server/event_router.rb`
- Create: `test/server/test_event_router.rb`

- [ ] **Step 1: Write failing test**

Create `test/server/test_event_router.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "async"

class TestEventRouter < Minitest::Test
  def test_subscribe_and_publish
    router   = SimpleA2a::Server::EventRouter.new
    received = []

    Async do
      sub = router.subscribe("task-1") { |e| received << e }
      router.publish("task-1", "event-a")
      router.publish("task-1", "event-b")
      router.unsubscribe("task-1", sub)
    end

    assert_equal ["event-a", "event-b"], received
  end

  def test_publish_to_unknown_channel_is_noop
    router = SimpleA2a::Server::EventRouter.new
    assert_nil router.publish("unknown-task", "event")
  end

  def test_close_channel_removes_it
    router = SimpleA2a::Server::EventRouter.new
    Async do
      router.subscribe("task-1") { |_e| }
      router.close_channel("task-1")
    end
    assert_nil router.publish("task-1", "event")
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/server/test_event_router.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Server::EventRouter`

- [ ] **Step 3: Create lib/simple_a2a/server/event_router.rb**

```ruby
# frozen_string_literal: true

require "typed_bus"

module SimpleA2a
  module Server
    class EventRouter
      def initialize
        @bus = TypedBus::MessageBus.new
        @subscriptions = {}  # { task_id => [sub_ids] }
      end

      def subscribe(task_id, &block)
        @bus.add_channel(task_id.to_sym) unless channel_exists?(task_id)
        sub_id = SecureRandom.hex(8)
        @subscriptions[task_id] ||= []
        @subscriptions[task_id] << sub_id

        @bus.subscribe(task_id.to_sym) do |delivery|
          block.call(delivery.message)
          delivery.ack!
        end

        sub_id
      end

      def publish(task_id, event)
        return nil unless channel_exists?(task_id)
        Async { @bus.publish(task_id.to_sym, event) }
        nil
      end

      def unsubscribe(task_id, sub_id)
        @subscriptions[task_id]&.delete(sub_id)
      end

      def close_channel(task_id)
        @subscriptions.delete(task_id)
        @bus.remove_channel(task_id.to_sym) if channel_exists?(task_id)
      end

      private

      def channel_exists?(task_id)
        @bus.channels.key?(task_id.to_sym)
      rescue
        false
      end
    end
  end
end
```

- [ ] **Step 4: Add require to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/server/event_router"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec ruby -Ilib -Itest test/server/test_event_router.rb
```

Expected: `3 runs, 4 assertions, 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add lib/simple_a2a/server/event_router.rb lib/simple_a2a.rb test/server/test_event_router.rb
git commit -m "feat: add Server::EventRouter wrapping TypedBus for per-task SSE fan-out"
```

---

## Task 15: Server::PushSender and Server::FalconRunner

**Files:**
- Create: `lib/simple_a2a/server/push_sender.rb`
- Create: `lib/simple_a2a/server/falcon_runner.rb`

- [ ] **Step 1: Create lib/simple_a2a/server/push_sender.rb**

No unit test for this component — it makes live HTTP calls. Covered by integration test in Task 23.

```ruby
# frozen_string_literal: true

require "jwt"
require "async/http/internet"

module SimpleA2a
  module Server
    class PushSender
      def initialize(storage:, event_router:, private_key: nil)
        @storage      = storage
        @event_router = event_router
        @private_key  = private_key
      end

      def watch(task_id)
        @event_router.subscribe(task_id) do |event|
          deliver(task_id, event)
        end
      end

      private

      def deliver(task_id, event)
        configs = @storage.list_push_configs(task_id)[:configs]
        return if configs.empty?

        payload = build_payload(event)

        configs.each do |config|
          next unless matches_event_types?(config, event)
          post_webhook(config, payload)
        end
      end

      def build_payload(event)
        if event.is_a?(Events::TaskStatusUpdateEvent)
          { "statusUpdate" => event.to_h }
        elsif event.is_a?(Events::TaskArtifactUpdateEvent)
          { "artifactUpdate" => event.to_h }
        else
          event.to_h
        end
      end

      def matches_event_types?(config, event)
        return true if config.event_types.nil? || config.event_types.empty?
        event_name = event.class.name.split("::").last
        config.event_types.include?(event_name)
      end

      def post_webhook(config, payload)
        headers = {
          "Content-Type" => "application/a2a+json"
        }
        headers.merge!(auth_headers(config)) if config.authentication_info

        Async do
          internet = Async::HTTP::Internet.new
          internet.post(config.webhook_url, headers.to_a, JSON.generate(payload))
        rescue => e
          SimpleA2a.logger&.error("Push notification failed: #{e.message}")
        ensure
          internet&.close
        end
      end

      def auth_headers(auth_info)
        case auth_info.scheme
        when "bearer"
          token = @private_key ? sign_jwt(auth_info.value) : auth_info.value
          { "Authorization" => "Bearer #{token}" }
        when "apiKey"
          header = auth_info.header_name || "X-API-Key"
          { header => auth_info.value }
        else
          {}
        end
      end

      def sign_jwt(audience)
        return audience unless @private_key
        payload = {
          iss: "simple_a2a",
          aud: audience,
          iat: Time.now.to_i,
          exp: Time.now.to_i + 300,
          jti: SecureRandom.uuid
        }
        JWT.encode(payload, @private_key, "RS256")
      end
    end
  end
end
```

- [ ] **Step 2: Create lib/simple_a2a/server/falcon_runner.rb**

```ruby
# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "falcon"
require "protocol/rack/adapter"

module SimpleA2a
  module Server
    module FalconRunner
      def self.run(app, port: 8000, host: "0.0.0.0", **options)
        endpoint   = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
        rack_app   = Protocol::Rack::Adapter.new(app)
        server     = Falcon::Server.new(rack_app, endpoint,
                                        protocol: Async::HTTP::Protocol::HTTP1,
                                        scheme:   "http")
        Sync do |task|
          server_task = task.async { server.run }

          trap("INT")  { server_task.stop }
          trap("TERM") { server_task.stop }

          server_task.wait
        end
      end
    end
  end
end
```

- [ ] **Step 3: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/server/push_sender"
require_relative "simple_a2a/server/falcon_runner"
```

- [ ] **Step 4: Verify no load errors**

```bash
bundle exec ruby -e "require 'simple_a2a'; puts 'OK'"
```

Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add lib/simple_a2a/server/push_sender.rb lib/simple_a2a/server/falcon_runner.rb lib/simple_a2a.rb
git commit -m "feat: add Server::PushSender (JWT webhook delivery) and FalconRunner"
```

---

## Task 16: Server::App (Roda routes)

**Files:**
- Create: `lib/simple_a2a/server/app.rb`
- Create: `test/server/test_app.rb`

- [ ] **Step 1: Write failing test**

Create `test/server/test_app.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "rack/test"

class EchoExecutor < SimpleA2a::Server::AgentExecutor
  def execute(context)
    text = context.message.text_content
    context.emit_status("working")
    artifact = SimpleA2a::Models::Artifact.new(
      name: "reply",
      parts: [SimpleA2a::Models::Part.text("Echo: #{text}")]
    )
    context.emit_artifact(artifact)
    context.emit_status("completed")
  end
end

class TestServerApp < Minitest::Test
  include Rack::Test::Methods

  M = SimpleA2a::Models

  def agent_card
    M::AgentCard.new(
      name:         "echo-agent",
      version:      "1.0.0",
      capabilities: M::AgentCapabilities.new,
      skills:       [M::AgentSkill.new(name: "echo")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
  end

  def app
    server = SimpleA2a::Server::Base.new(
      agent_card:     agent_card,
      executor_class: EchoExecutor
    )
    server.to_app
  end

  def test_get_agent_card
    get "/agentCard"
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert_equal "echo-agent", body["name"]
  end

  def test_send_message_via_rest
    message = M::Message.user("hello")
    post "/messages",
         JSON.generate({ "message" => message.to_h }),
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert body.key?("id")
    assert_equal "completed", body["status"]["state"]
  end

  def test_send_message_via_jsonrpc
    message = M::Message.user("test")
    payload = {
      "jsonrpc"     => "2.0",
      "method"      => "SendMessage",
      "params"      => { "message" => message.to_h },
      "id"          => "r-1",
      "a2a-version" => "1.0"
    }
    post "/", JSON.generate(payload), { "CONTENT_TYPE" => "application/json" }
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert_equal "2.0",   body["jsonrpc"]
    assert_equal "r-1",   body["id"]
    assert body["result"].key?("id")
  end

  def test_get_task
    message = M::Message.user("hello")
    post "/messages",
         JSON.generate({ "message" => message.to_h }),
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }
    task_id = JSON.parse(last_response.body)["id"]

    get "/tasks/#{task_id}", {}, { "HTTP_A2A_VERSION" => "1.0" }
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert_equal task_id, body["id"]
  end

  def test_get_unknown_task_returns_404
    get "/tasks/nonexistent", {}, { "HTTP_A2A_VERSION" => "1.0" }
    assert_equal 404, last_response.status
  end

  def test_unsupported_version_returns_error
    post "/messages",
         JSON.generate({ "message" => M::Message.user("hi").to_h }),
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "9.9" }
    assert_equal 400, last_response.status
  end

  def test_list_tasks
    get "/tasks", {}, { "HTTP_A2A_VERSION" => "1.0" }
    assert last_response.ok?
    body = JSON.parse(last_response.body)
    assert body.key?("tasks")
  end

  def test_cancel_unknown_task_returns_error
    post "/tasks/bad-id:cancel", "{}", { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }
    assert_equal 404, last_response.status
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec ruby -Ilib -Itest test/server/test_app.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Server::Base` (or App)

- [ ] **Step 3: Create lib/simple_a2a/server/app.rb**

```ruby
# frozen_string_literal: true

require "roda"

module SimpleA2a
  module Server
    class App < Roda
      SUPPORTED_VERSIONS = %w[1.0 0.3].freeze

      plugin :json
      plugin :json_parser
      plugin :halt
      plugin :all_verbs

      def self.build(server_base)
        app = Class.new(self)
        app.instance_variable_set(:@server, server_base)
        app.define_method(:server) { self.class.instance_variable_get(:@server) }
        app
      end

      route do |r|
        check_version!(r)

        r.on "agentCard" do
          r.get "extended" do
            response["Content-Type"] = "application/json"
            server.agent_card.to_h
          end

          r.get do
            response["Content-Type"] = "application/json"
            server.agent_card.to_h
          end
        end

        r.on "messages" do
          r.post "stream" do
            handle_streaming_message(r)
          end

          r.post do
            handle_send_message(r)
          end
        end

        r.on "tasks" do
          r.get do
            filters = {
              context_id:  r.params["contextId"],
              status:      r.params["status"],
              page_size:   r.params["pageSize"]&.to_i || 50,
              page_token:  r.params["pageToken"]
            }.compact
            result = server.list_tasks(**filters)
            {
              "tasks"         => result[:tasks].map(&:to_h),
              "nextPageToken" => result[:next_page_token],
              "totalSize"     => result[:total_size]
            }
          end

          r.on String do |task_id|
            r.post "cancel" do
              task = server.cancel_task(task_id)
              r.halt(404, json_error("TaskNotFound", "Task not found")) unless task
              task.to_h
            end

            r.get "stream" do
              handle_task_subscribe(r, task_id)
            end

            r.on "pushNotificationConfigs" do
              r.post do
                cfg = Models::PushNotificationConfig.from_hash(r.params)
                cfg.id      ||= SecureRandom.uuid
                cfg.task_id ||= task_id
                result = server.create_push_config(task_id, cfg)
                result.to_h
              end

              r.get String do |config_id|
                cfg = server.get_push_config(task_id, config_id)
                r.halt(404, json_error("NotFound", "Config not found")) unless cfg
                cfg.to_h
              end

              r.delete String do |config_id|
                server.delete_push_config(task_id, config_id)
                response.status = 204
                ""
              end

              r.get do
                result = server.list_push_configs(task_id)
                { "configs" => result[:configs].map(&:to_h), "nextPageToken" => result[:next_page_token] }
              end
            end

            r.get do
              history_length = r.params["historyLength"]&.to_i
              task = server.get_task(task_id, history_length: history_length)
              r.halt(404, json_error("TaskNotFound", "Task not found")) unless task
              task.to_h
            end
          end
        end

        r.post do
          handle_jsonrpc(r)
        end
      end

      private

      def check_version!(r)
        version = r.env["HTTP_A2A_VERSION"] || "0.3"
        unless SUPPORTED_VERSIONS.include?(version)
          r.halt(400, json_error("VersionNotSupported", "Unsupported A2A-Version: #{version}"))
        end
      end

      def handle_send_message(r)
        params  = r.params
        message = Models::Message.from_hash(params["message"])
        config  = Models::SendMessageConfiguration.from_hash(params["configuration"] || {})
        result  = server.send_message(message, config)
        result.to_h
      end

      def handle_jsonrpc(r)
        req = JSONRPC::Request.parse(r.env["rack.input"].read)
        result = dispatch_jsonrpc(req)
        JSONRPC::Response.success(id: req.id, result: result).to_h
      rescue JSONRPC::ParseError => e
        JSONRPC::Response.error(id: nil, code: JSONRPC::ErrorCodes::PARSE_ERROR, message: e.message).to_h
      rescue JSONRPC::InvalidRequestError => e
        JSONRPC::Response.error(id: nil, code: JSONRPC::ErrorCodes::INVALID_REQUEST, message: e.message).to_h
      rescue TaskNotFoundError => e
        JSONRPC::Response.error(id: nil, code: JSONRPC::ErrorCodes::TASK_NOT_FOUND, message: e.message).to_h
      end

      def dispatch_jsonrpc(req)
        p = req.params
        case req.method
        when "SendMessage"
          message = Models::Message.from_hash(p["message"])
          config  = Models::SendMessageConfiguration.from_hash(p["configuration"] || {})
          server.send_message(message, config).to_h
        when "GetTask"
          task = server.get_task(p["id"], history_length: p["historyLength"])
          raise TaskNotFoundError, "Task not found: #{p["id"]}" unless task
          task.to_h
        when "ListTasks"
          result = server.list_tasks(**symbolize_filters(p))
          { "tasks" => result[:tasks].map(&:to_h), "nextPageToken" => result[:next_page_token] }
        when "CancelTask"
          task = server.cancel_task(p["id"])
          raise TaskNotFoundError, "Task not found: #{p["id"]}" unless task
          task.to_h
        when "GetExtendedAgentCard"
          server.agent_card.to_h
        else
          raise UnsupportedOperationError, "Unknown method: #{req.method}"
        end
      end

      def handle_streaming_message(r)
        response["Content-Type"]  = "text/event-stream"
        response["Cache-Control"] = "no-cache"
        response["Connection"]    = "keep-alive"
        params  = r.params
        message = Models::Message.from_hash(params["message"])
        config  = Models::SendMessageConfiguration.from_hash(params["configuration"] || {})
        request_id = SecureRandom.uuid

        stream_body = proc do |out|
          server.send_streaming_message(message, config) do |event|
            out.write(event.sse_format(jsonrpc_id: request_id))
            out.flush
          end
          out.close
        end

        r.halt([200, response.headers, stream_body])
      end

      def handle_task_subscribe(r, task_id)
        task = server.get_task(task_id)
        r.halt(404, json_error("TaskNotFound", "Task not found")) unless task
        return task.to_h if task.terminal?

        response["Content-Type"]  = "text/event-stream"
        response["Cache-Control"] = "no-cache"
        request_id = SecureRandom.uuid

        stream_body = proc do |out|
          server.subscribe_to_task(task_id) do |event|
            out.write(event.sse_format(jsonrpc_id: request_id))
            out.flush
          end
          out.close
        end

        r.halt([200, response.headers, stream_body])
      end

      def json_error(type, message)
        JSON.generate({ "error" => { "type" => type, "message" => message } })
      end

      def symbolize_filters(params)
        {
          context_id: params["contextId"],
          status:     params["status"],
          page_size:  params["pageSize"]&.to_i || 50,
          page_token: params["pageToken"]
        }.compact
      end
    end
  end
end
```

- [ ] **Step 4: Add require to lib/simple_a2a.rb (before base.rb)**

```ruby
require_relative "simple_a2a/server/app"
```

- [ ] **Step 5: Create Server::Base stub so tests can load**

We need `Server::Base` before we can test App. Create `lib/simple_a2a/server/base.rb` with a minimal version:

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Server
    class Base
      attr_reader :agent_card, :storage, :event_router

      def initialize(agent_card:, executor_class:, storage: nil, **options)
        @agent_card     = agent_card
        @executor_class = executor_class
        @storage        = storage || Storage::Memory.new
        @event_router   = EventRouter.new
      end

      def to_app
        App.build(self)
      end

      def run(port: 8000, host: "0.0.0.0")
        FalconRunner.run(to_app, port: port, host: host)
      end

      def send_message(message, configuration = nil)
        task = create_task(message)
        ctx  = build_context(task, message, configuration)
        executor = @executor_class.new
        executor.execute(ctx)
        task.complete! if task.state == Models::Types::TaskState::WORKING
        @storage.save_task(task)
        task
      end

      def send_streaming_message(message, configuration = nil, &block)
        task = create_task(message)
        ctx  = build_context(task, message, configuration, &block)
        executor = @executor_class.new
        executor.execute(ctx)
        unless task.terminal?
          task.complete!
          @storage.save_task(task)
          event = Events::TaskStatusUpdateEvent.new(
            task_id: task.id, context_id: task.context_id, status: task.status
          )
          block.call(event)
        end
      end

      def get_task(id, history_length: nil)
        task = @storage.get_task(id)
        return nil unless task
        if history_length
          task = task.dup
          task.history = task.history&.last(history_length) || []
        end
        task
      end

      def list_tasks(**filters)
        @storage.list_tasks(**filters)
      end

      def cancel_task(id)
        task = @storage.get_task(id)
        return nil unless task
        return task if task.terminal?
        task.cancel!
        @storage.save_task(task)
        task
      end

      def subscribe_to_task(task_id, &block)
        done = false
        @event_router.subscribe(task_id) do |event|
          block.call(event)
          done = true if event.is_a?(Events::TaskStatusUpdateEvent) && event.status.terminal?
        end
        sleep 0.05 until done
      end

      def create_push_config(task_id, config)
        config.id      ||= SecureRandom.uuid
        config.task_id ||= task_id
        @storage.create_push_config(config)
      end

      def get_push_config(task_id, config_id)
        @storage.get_push_config(task_id, config_id)
      end

      def list_push_configs(task_id, **opts)
        @storage.list_push_configs(task_id, **opts)
      end

      def delete_push_config(task_id, config_id)
        @storage.delete_push_config(task_id, config_id)
      end

      private

      def create_task(message)
        task = Models::Task.new(
          context_id: message.context_id || SecureRandom.uuid,
          status:     Models::TaskStatus.new(state: Models::Types::TaskState::SUBMITTED)
        )
        task.history = [message]
        @storage.save_task(task)
        task
      end

      def build_context(task, message, configuration, &block)
        on_event = if block
          ->(event) {
            @event_router.publish(task.id, event)
            block.call(event)
          }
        else
          ->(event) { @event_router.publish(task.id, event) }
        end

        Context.new(
          task:          task,
          message:       message,
          storage:       @storage,
          on_event:      on_event,
          configuration: configuration
        )
      end
    end
  end
end
```

- [ ] **Step 6: Add require to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/server/base"
```

- [ ] **Step 7: Run app tests**

```bash
bundle exec ruby -Ilib -Itest test/server/test_app.rb
```

Expected: `8 runs, 11 assertions, 0 failures, 0 errors`

- [ ] **Step 8: Commit**

```bash
git add lib/simple_a2a/server/app.rb lib/simple_a2a/server/base.rb lib/simple_a2a.rb test/server/test_app.rb
git commit -m "feat: add Server::App (Roda routes) and Server::Base"
```

---

## Task 17: Client::SSE and Client::Base

**Files:**
- Create: `lib/simple_a2a/client/sse.rb`
- Create: `lib/simple_a2a/client/base.rb`
- Create: `test/client/test_client.rb`

- [ ] **Step 1: Write failing test**

Create `test/client/test_client.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestSSEParser < Minitest::Test
  def test_parses_data_lines
    parser = SimpleA2a::Client::SSEParser.new
    events = []
    parser.feed("data: {\"foo\":\"bar\"}\n\n") { |e| events << e }
    assert_equal 1, events.length
    assert_equal({ "foo" => "bar" }, events[0])
  end

  def test_parses_multiline_data
    parser = SimpleA2a::Client::SSEParser.new
    events = []
    parser.feed("data: {\"a\":1}\n") { |_e| }
    parser.feed("data: {\"b\":2}\n\n") { |e| events << e }
    assert_equal 1, events.length
  end

  def test_ignores_comment_lines
    parser = SimpleA2a::Client::SSEParser.new
    events = []
    parser.feed(": keep-alive\n\ndata: {\"ok\":true}\n\n") { |e| events << e }
    assert_equal 1, events.length
  end
end

class TestClientBase < Minitest::Test
  def test_initializes_with_base_url
    client = SimpleA2a::Client::Base.new(base_url: "http://localhost:8000")
    assert_equal "http://localhost:8000", client.base_url
  end

  def test_a2a_version_default
    client = SimpleA2a::Client::Base.new(base_url: "http://localhost:8000")
    assert_equal "1.0", client.a2a_version
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
mkdir -p test/client
bundle exec ruby -Ilib -Itest test/client/test_client.rb
```

Expected: `NameError: uninitialized constant SimpleA2a::Client`

- [ ] **Step 3: Create lib/simple_a2a/client/sse.rb**

```ruby
# frozen_string_literal: true

module SimpleA2a
  module Client
    class SSEParser
      def initialize
        @buffer = +""
        @data_lines = []
      end

      def feed(chunk, &block)
        @buffer << chunk
        process_buffer(&block)
      end

      private

      def process_buffer(&block)
        while (idx = @buffer.index("\n\n"))
          event_text = @buffer.slice!(0, idx + 2)
          parse_event(event_text, &block)
        end
      end

      def parse_event(text, &block)
        data_lines = []
        text.each_line do |line|
          line = line.chomp
          next if line.start_with?(":")
          next if line.empty?

          if line.start_with?("data: ")
            data_lines << line.sub("data: ", "")
          end
        end

        return if data_lines.empty?
        combined = data_lines.join("\n")
        parsed   = JSON.parse(combined)
        block.call(parsed) if block
      rescue JSON::ParserError
        nil
      end
    end
  end
end
```

- [ ] **Step 4: Create lib/simple_a2a/client/base.rb**

```ruby
# frozen_string_literal: true

require "async"
require "async/http/internet"

module SimpleA2a
  module Client
    class Base
      attr_reader :base_url, :a2a_version

      def initialize(base_url:, a2a_version: "1.0", auth: nil, **options)
        @base_url    = base_url.chomp("/")
        @a2a_version = a2a_version
        @auth        = auth
      end

      def agent_card
        Models::AgentCard.from_hash(get("/agentCard"))
      end

      def send_message(message, configuration: nil)
        params = { "message" => message.to_h }
        params["configuration"] = configuration.to_h if configuration
        result = post("/messages", params)
        Models::Task.from_hash(result)
      end

      def get_task(id, history_length: nil)
        query  = history_length ? "?historyLength=#{history_length}" : ""
        result = get("/tasks/#{id}#{query}")
        Models::Task.from_hash(result)
      end

      def list_tasks(context_id: nil, status: nil, page_size: 50, page_token: nil)
        query = URI.encode_www_form([
          context_id && ["contextId", context_id],
          status     && ["status",    status],
          ["pageSize", page_size],
          page_token && ["pageToken", page_token]
        ].compact)
        result = get("/tasks?#{query}")
        {
          tasks:           (result["tasks"] || []).map { |t| Models::Task.from_hash(t) },
          next_page_token: result["nextPageToken"]
        }
      end

      def cancel_task(id)
        result = post("/tasks/#{id}:cancel", {})
        Models::Task.from_hash(result)
      end

      def send_streaming_message(message, config: nil, &block)
        params = { "message" => message.to_h }
        params["configuration"] = config.to_h if config
        stream_post("/messages:stream", params, &block)
      end

      def subscribe_to_task(id, &block)
        stream_get("/tasks/#{id}:stream", &block)
      end

      def create_push_config(task_id, webhook_url:, **opts)
        payload = { "taskId" => task_id, "webhookUrl" => webhook_url }.merge(opts)
        result  = post("/tasks/#{task_id}/pushNotificationConfigs", payload)
        Models::PushNotificationConfig.from_hash(result)
      end

      def get_push_config(task_id, config_id)
        Models::PushNotificationConfig.from_hash(
          get("/tasks/#{task_id}/pushNotificationConfigs/#{config_id}")
        )
      end

      def list_push_configs(task_id)
        result = get("/tasks/#{task_id}/pushNotificationConfigs")
        (result["configs"] || []).map { |c| Models::PushNotificationConfig.from_hash(c) }
      end

      def delete_push_config(task_id, config_id)
        delete_req("/tasks/#{task_id}/pushNotificationConfigs/#{config_id}")
        true
      end

      def wait_for_task(id, timeout: 60, interval: 1)
        deadline = Time.now + timeout
        loop do
          task = get_task(id)
          return task if task.terminal? || task.interrupted?
          raise TimeoutError, "Task #{id} did not complete within #{timeout}s" if Time.now > deadline
          sleep interval
        end
      end

      private

      def default_headers
        h = {
          "Content-Type" => "application/json",
          "A2A-Version"  => @a2a_version
        }
        h.merge!(auth_header) if @auth
        h
      end

      def auth_header
        case @auth&.dig(:type)&.to_sym
        when :bearer  then { "Authorization" => "Bearer #{@auth[:token]}" }
        when :api_key then { (@auth[:header] || "X-API-Key") => @auth[:key] }
        else {}
        end
      end

      def get(path)
        Sync do
          internet = Async::HTTP::Internet.new
          response = internet.get("#{@base_url}#{path}", default_headers.to_a)
          JSON.parse(response.read)
        ensure
          internet&.close
        end
      end

      def post(path, body)
        Sync do
          internet = Async::HTTP::Internet.new
          response = internet.post(
            "#{@base_url}#{path}",
            default_headers.to_a,
            JSON.generate(body)
          )
          JSON.parse(response.read)
        ensure
          internet&.close
        end
      end

      def delete_req(path)
        Sync do
          internet = Async::HTTP::Internet.new
          internet.delete("#{@base_url}#{path}", default_headers.to_a)
        ensure
          internet&.close
        end
      end

      def stream_post(path, body, &block)
        return enum_for(:stream_post, path, body) unless block
        parser = SSEParser.new
        Sync do
          internet = Async::HTTP::Internet.new
          response = internet.post(
            "#{@base_url}#{path}",
            default_headers.to_a,
            JSON.generate(body)
          )
          response.body.each do |chunk|
            parser.feed(chunk) do |event_data|
              result = event_data["result"]
              next unless result
              sr = parse_stream_response(result)
              block.call(sr) if sr
            end
          end
        ensure
          internet&.close
        end
      end

      def stream_get(path, &block)
        return enum_for(:stream_get, path) unless block
        parser = SSEParser.new
        Sync do
          internet = Async::HTTP::Internet.new
          response = internet.get("#{@base_url}#{path}", default_headers.to_a)
          response.body.each do |chunk|
            parser.feed(chunk) do |event_data|
              result = event_data["result"]
              next unless result
              sr = parse_stream_response(result)
              block.call(sr) if sr
            end
          end
        ensure
          internet&.close
        end
      end

      def parse_stream_response(result)
        if result["status"]
          Models::StreamResponse.new(
            status_update: Events::TaskStatusUpdateEvent.from_hash(result)
          )
        elsif result["artifact"]
          Models::StreamResponse.new(
            artifact_update: Events::TaskArtifactUpdateEvent.from_hash(result)
          )
        elsif result["id"]
          Models::StreamResponse.new(task: Models::Task.from_hash(result))
        end
      end
    end
  end
end
```

- [ ] **Step 5: Add requires to lib/simple_a2a.rb**

```ruby
require_relative "simple_a2a/client/sse"
require_relative "simple_a2a/client/base"
```

- [ ] **Step 6: Run client tests**

```bash
bundle exec ruby -Ilib -Itest test/client/test_client.rb
```

Expected: `5 runs, 7 assertions, 0 failures, 0 errors`

- [ ] **Step 7: Commit**

```bash
git add lib/simple_a2a/client/ lib/simple_a2a.rb test/client/test_client.rb
git commit -m "feat: add Client::SSEParser and Client::Base with async-http"
```

---

## Task 18: Top-level Aliases, Full Test Suite, and Final Cleanup

**Files:**
- Modify: `lib/simple_a2a.rb`

- [ ] **Step 1: Add convenience aliases and final require order to lib/simple_a2a.rb**

Replace the full contents of `lib/simple_a2a.rb` with the correct ordered require list:

```ruby
# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require "uri"

require_relative "simple_a2a/version"
require_relative "simple_a2a/errors"

require_relative "simple_a2a/models/base"
require_relative "simple_a2a/models/types"
require_relative "simple_a2a/models/part"
require_relative "simple_a2a/models/message"
require_relative "simple_a2a/models/artifact"
require_relative "simple_a2a/models/task_status"
require_relative "simple_a2a/models/task"
require_relative "simple_a2a/models/stream_response"
require_relative "simple_a2a/models/send_message_config"
require_relative "simple_a2a/models/push_notification"
require_relative "simple_a2a/models/agent_card"
require_relative "simple_a2a/models/security_scheme"

require_relative "simple_a2a/events/task_status_update"
require_relative "simple_a2a/events/task_artifact_update"

require_relative "simple_a2a/jsonrpc/error"
require_relative "simple_a2a/jsonrpc/request"
require_relative "simple_a2a/jsonrpc/response"

require_relative "simple_a2a/storage/base"
require_relative "simple_a2a/storage/memory"

require_relative "simple_a2a/server/agent_executor"
require_relative "simple_a2a/server/context"
require_relative "simple_a2a/server/event_router"
require_relative "simple_a2a/server/push_sender"
require_relative "simple_a2a/server/falcon_runner"
require_relative "simple_a2a/server/app"
require_relative "simple_a2a/server/base"

require_relative "simple_a2a/client/sse"
require_relative "simple_a2a/client/base"

module SimpleA2a
  class << self
    attr_accessor :logger
  end

  SimpleA2aServer   = Server::Base
  SimpleA2aClient   = Client::Base
  SimpleA2aExecutor = Server::AgentExecutor
end
```

- [ ] **Step 2: Run the full test suite**

```bash
bundle exec rake test
```

Expected: All tests pass. `0 failures, 0 errors`

- [ ] **Step 3: Fix any load-order failures found in step 2**

If any `NameError` appears because one require references a constant defined in a later require, reorder the `require_relative` lines in `lib/simple_a2a.rb` to resolve it.

- [ ] **Step 4: Commit**

```bash
git add lib/simple_a2a.rb
git commit -m "feat: finalize require order and add top-level convenience aliases"
```

---

## Task 19: Integration Test

**Files:**
- Create: `test/integration/test_round_trip.rb`

- [ ] **Step 1: Write integration test**

Create `test/integration/test_round_trip.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "rack/test"

class IntegrationExecutor < SimpleA2a::Server::AgentExecutor
  def execute(context)
    input = context.message.text_content
    context.emit_status("working")
    artifact = SimpleA2a::Models::Artifact.new(
      name:  "answer",
      parts: [SimpleA2a::Models::Part.text("Processed: #{input}")]
    )
    context.emit_artifact(artifact)
    context.emit_status("completed")
  end
end

class TestIntegration < Minitest::Test
  include Rack::Test::Methods

  M = SimpleA2a::Models

  def agent_card
    M::AgentCard.new(
      name:         "integration-agent",
      version:      "1.0.0",
      capabilities: M::AgentCapabilities.new(streaming: true),
      skills:       [M::AgentSkill.new(name: "process")],
      interfaces:   [M::AgentInterface.new(type: "json-rpc", url: "http://localhost", version: "1.0")]
    )
  end

  def app
    SimpleA2a::Server::Base.new(
      agent_card:     agent_card,
      executor_class: IntegrationExecutor
    ).to_app
  end

  def test_full_send_message_round_trip
    message = M::Message.user("hello world")
    post "/messages",
         JSON.generate({ "message" => message.to_h }),
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }

    assert last_response.ok?, "Expected 200 but got #{last_response.status}: #{last_response.body}"
    task = JSON.parse(last_response.body)
    assert_equal "completed", task["status"]["state"]
    assert_equal 1, task["artifacts"].length
    assert_includes task["artifacts"][0]["parts"][0]["text"], "hello world"
  end

  def test_agent_card_discoverable
    get "/agentCard", {}, { "HTTP_A2A_VERSION" => "1.0" }
    assert last_response.ok?
    card = JSON.parse(last_response.body)
    assert_equal "integration-agent", card["name"]
    assert_equal true, card["capabilities"]["streaming"]
  end

  def test_task_persists_after_send
    message = M::Message.user("persist me")
    post "/messages",
         JSON.generate({ "message" => message.to_h }),
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }
    task_id = JSON.parse(last_response.body)["id"]

    get "/tasks/#{task_id}", {}, { "HTTP_A2A_VERSION" => "1.0" }
    assert last_response.ok?
    retrieved = JSON.parse(last_response.body)
    assert_equal task_id, retrieved["id"]
    assert_equal "completed", retrieved["status"]["state"]
  end

  def test_cancel_completed_task_returns_task_unchanged
    message = M::Message.user("cancel test")
    post "/messages",
         JSON.generate({ "message" => message.to_h }),
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }
    task_id = JSON.parse(last_response.body)["id"]

    post "/tasks/#{task_id}:cancel", "{}",
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }
    assert last_response.ok?
    cancelled = JSON.parse(last_response.body)
    assert_equal "completed", cancelled["status"]["state"]
  end

  def test_jsonrpc_send_message
    message = M::Message.user("via jsonrpc")
    payload = {
      "jsonrpc"     => "2.0",
      "method"      => "SendMessage",
      "params"      => { "message" => message.to_h },
      "id"          => "test-req-1",
      "a2a-version" => "1.0"
    }
    post "/", JSON.generate(payload),
         { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }
    assert last_response.ok?
    response = JSON.parse(last_response.body)
    assert_equal "2.0",          response["jsonrpc"]
    assert_equal "test-req-1",   response["id"]
    assert_equal "completed",    response["result"]["status"]["state"]
  end
end
```

- [ ] **Step 2: Run integration tests**

```bash
mkdir -p test/integration
bundle exec ruby -Ilib -Itest test/integration/test_round_trip.rb
```

Expected: `5 runs, 14 assertions, 0 failures, 0 errors`

- [ ] **Step 3: Run full test suite one final time**

```bash
bundle exec rake test
```

Expected: All tasks pass. `0 failures, 0 errors`

- [ ] **Step 4: Final commit**

```bash
git add test/integration/test_round_trip.rb
git commit -m "test: add end-to-end integration test for send/retrieve/cancel/jsonrpc"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] All 11 A2A operations exposed (SendMessage, SendStreamingMessage, GetTask, ListTasks, CancelTask, SubscribeToTask, push notification CRUD, GetExtendedAgentCard)
- [x] JSON-RPC 2.0 binding (Task 11, 16)
- [x] HTTP+REST binding (Task 16)
- [x] All data models (Tasks 4–9)
- [x] AgentCard served at `/agentCard` (Task 16)
- [x] SSE streaming server side (Task 16) and client side (Task 17)
- [x] Push notification config CRUD (Tasks 8, 16)
- [x] TypedBus event fan-out (Task 14)
- [x] JWT push notification signing (Task 15)
- [x] Async-native storage (Task 12)
- [x] A2A-Version header validation (Task 16)
- [x] Convenience aliases (Task 18)
- [x] Integration test (Task 19)

**Out of scope (confirmed):** gRPC binding, Redis/PostgreSQL storage, AgentCard signing, OpenTelemetry, Rails engine.
