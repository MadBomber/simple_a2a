# frozen_string_literal: true

require "test_helper"

class TestAgentCard < Minitest::Test
  def minimal_card
    A2A::Models::AgentCard.new(
      name: "TestAgent",
      version: "1.0",
      capabilities: A2A::Models::AgentCapabilities.new,
      skills: [
        A2A::Models::AgentSkill.new(name: "ask")
      ],
      interfaces: [
        A2A::Models::AgentInterface.new(type: "json-rpc", url: "https://example.com/a2a", version: "1.0")
      ]
    )
  end


  def test_valid_minimal_card
    assert minimal_card.valid?
  end


  def test_invalid_without_name
    card = minimal_card
    card.name = nil
    refute card.valid?
  end


  def test_invalid_without_version
    card = minimal_card
    card.version = nil
    refute card.valid?
  end


  def test_invalid_without_capabilities
    card = minimal_card
    card.capabilities = nil
    refute card.valid?
  end


  def test_capabilities_defaults
    caps = A2A::Models::AgentCapabilities.new
    refute caps.streaming
    refute caps.push_notifications
    refute caps.extended_agent_card
  end


  def test_capabilities_custom
    caps = A2A::Models::AgentCapabilities.new(streaming: true, push_notifications: true)
    assert caps.streaming
    assert caps.push_notifications
    refute caps.extended_agent_card
  end


  def test_agent_provider
    prov = A2A::Models::AgentProvider.new(name: "Acme Corp", url: "https://acme.example.com")
    assert prov.valid?
    assert_equal "Acme Corp", prov.name
  end


  def test_agent_provider_requires_name
    prov = A2A::Models::AgentProvider.new(name: nil)
    refute prov.valid?
  end


  def test_agent_skill_requires_name
    skill = A2A::Models::AgentSkill.new(name: nil)
    refute skill.valid?
  end


  def test_agent_interface_requires_all_fields
    iface = A2A::Models::AgentInterface.new(type: "json-rpc", url: nil, version: "1.0")
    refute iface.valid?
  end


  def test_to_h_roundtrip
    card = minimal_card
    h = card.to_h
    card2 = A2A::Models::AgentCard.from_hash(h)
    assert_equal "TestAgent", card2.name
    assert_equal "1.0", card2.version
    assert_instance_of A2A::Models::AgentCapabilities, card2.capabilities
    assert_equal 1, card2.skills.length
    assert_equal "ask", card2.skills.first.name
    assert_equal 1, card2.interfaces.length
    assert_equal "https://example.com/a2a", card2.interfaces.first.url
  end


  def test_from_hash_camel_case
    h = {
      "name" => "MyAgent",
      "version" => "2.0",
      "capabilities" => { "streaming" => true, "pushNotifications" => false, "extendedAgentCard" => false },
      "skills" => [{ "name" => "compute" }],
      "interfaces" => [{ "type" => "json-rpc", "url" => "https://api.example.com", "version" => "1.0" }]
    }
    card = A2A::Models::AgentCard.from_hash(h)
    assert_equal "MyAgent", card.name
    assert card.capabilities.streaming
    assert_equal "compute", card.skills.first.name
  end


  def test_with_provider
    card = minimal_card
    card.provider = A2A::Models::AgentProvider.new(name: "Acme")
    h = card.to_h
    card2 = A2A::Models::AgentCard.from_hash(h)
    assert_instance_of A2A::Models::AgentProvider, card2.provider
    assert_equal "Acme", card2.provider.name
  end
end


class TestSecurityScheme < Minitest::Test
  def test_requires_type
    ss = A2A::Models::SecurityScheme.new(type: nil)
    refute ss.valid?
  end


  def test_http_scheme
    ss = A2A::Models::SecurityScheme.new(type: "http", scheme: "bearer", bearer_format: "JWT")
    assert ss.valid?
    assert_equal "http", ss.type
    assert_equal "bearer", ss.scheme
    assert_equal "JWT", ss.bearer_format
  end


  def test_api_key_scheme
    ss = A2A::Models::SecurityScheme.new(type: "apiKey", in: "header", name: "X-Api-Key")
    assert ss.valid?
    assert_equal "apiKey", ss.type
  end


  def test_to_h_camel_case_keys
    ss = A2A::Models::SecurityScheme.new(type: "http", scheme: "bearer", bearer_format: "JWT")
    h = ss.to_h
    assert h.key?("type")
    assert h.key?("bearerFormat")
    refute h.key?("bearer_format")
  end


  def test_from_hash_roundtrip
    h = { "type" => "http", "scheme" => "bearer", "bearerFormat" => "JWT" }
    ss = A2A::Models::SecurityScheme.from_hash(h)
    assert_equal "http", ss.type
    assert_equal "bearer", ss.scheme
    assert_equal "JWT", ss.bearer_format
  end
end
