# frozen_string_literal: true

require "test_helper"

class TestModelsBase < Minitest::Test
  class Widget < A2A::Models::Base
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
    sub = Class.new(Widget) { attribute :extra }
    assert_includes sub.attributes.keys, :widget_id
    assert_includes sub.attributes.keys, :extra
  end

  def test_nested_model_coercion
    inner_class = Class.new(A2A::Models::Base) { attribute :value }
    outer_class = Class.new(A2A::Models::Base)
    outer_class.attribute :inner, type: inner_class

    outer = outer_class.from_hash({ "inner" => { "value" => "hello" } })
    assert_instance_of inner_class, outer.inner
    assert_equal "hello", outer.inner.value
  end

  def test_array_of_models_coercion
    item_class = Class.new(A2A::Models::Base) { attribute :label }
    container_class = Class.new(A2A::Models::Base)
    container_class.attribute :items, type: [item_class], default: -> { [] }

    c = container_class.from_hash({ "items" => [{ "label" => "a" }, { "label" => "b" }] })
    assert_equal 2, c.items.length
    assert_instance_of item_class, c.items[0]
    assert_equal "b", c.items[1].label
  end

  def test_serialize_hash_attribute
    klass = Class.new(A2A::Models::Base) { attribute :metadata }
    obj = klass.new(metadata: { "key" => "value", "num" => 42 })
    h = obj.to_h
    assert_equal({ "key" => "value", "num" => 42 }, h["metadata"])
  end

  def test_serialize_time_attribute
    klass = Class.new(A2A::Models::Base) { attribute :created_at }
    t = Time.now
    obj = klass.new(created_at: t)
    h = obj.to_h
    assert_equal t.iso8601, h["createdAt"]
  end

  def test_coerce_returns_val_when_type_mismatch_and_not_hash
    klass = Class.new(A2A::Models::Base) { attribute :count, type: Integer }
    obj = klass.from_hash({ "count" => "42" })
    assert_equal "42", obj.count
  end
end
