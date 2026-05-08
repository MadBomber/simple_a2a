#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/03_llm_research/client.rb [topic]
#
# Start the server first:
#   bundle exec ruby examples/03_llm_research/server.rb

require_relative "../common_config"

BASE_URL      = "http://localhost:9292"
ANTHROPIC_URL = "#{BASE_URL}/anthropic"
OPENAI_URL    = "#{BASE_URL}/openai"
EVALUATOR_URL = "#{BASE_URL}/evaluator"

topic = ARGV.first || "research all shortcomings and defects and criticisms of the agent-to-agent protocol specification; summarize what is wrong with the spec"

def banner(text)
  bar = "─" * (text.length + 4)
  puts "┌#{bar}┐"
  puts "│  #{text}  │"
  puts "└#{bar}┘"
end

def collect_streaming_response(url, topic)
  client = A2A.sse_client(url: url)
  text   = +""

  client.send_subscribe(message: A2A::Models::Message.user(topic)) do |event|
    case event
    when A2A::Models::TaskArtifactUpdateEvent
      text << event.artifact.parts.filter_map(&:text).join
    end
  end

  text
end

# ---------------------------------------------------------------------------
# 1. Research phase — query both agents in parallel
# ---------------------------------------------------------------------------
banner "Research Phase: \"#{topic}\""
puts
puts "Querying Anthropic (claude-sonnet-4-6) and OpenAI (gpt-5.4) in parallel…"
puts "This may take several minutes for complex topics."
puts

anthropic_text = nil
openai_text    = nil
anthropic_err  = nil
openai_err     = nil

anthropic_thread = Thread.new do
  anthropic_text = collect_streaming_response(ANTHROPIC_URL, topic)
rescue => e
  anthropic_err = e
end

openai_thread = Thread.new do
  openai_text = collect_streaming_response(OPENAI_URL, topic)
rescue => e
  openai_err = e
end

start_time      = Time.now
progress_thread = Thread.new do
  loop do
    sleep 30
    elapsed = (Time.now - start_time).to_i
    $stderr.puts "  (still waiting for LLM responses... #{elapsed}s elapsed)"
  end
end

anthropic_thread.join
openai_thread.join
progress_thread.kill

if anthropic_err
  warn "Anthropic agent error: #{anthropic_err.message}"
  exit 1
end

if openai_err
  warn "OpenAI agent error: #{openai_err.message}"
  exit 1
end

# ---------------------------------------------------------------------------
# 2. Display research responses
# ---------------------------------------------------------------------------
puts "=== Claude Response (#{anthropic_text.length} chars) ==="
puts anthropic_text
puts
puts "=== GPT-5.4 Response (#{openai_text.length} chars) ==="
puts openai_text
puts

# ---------------------------------------------------------------------------
# 3. Evaluation phase — send both responses to the evaluator
# ---------------------------------------------------------------------------
banner "Evaluation Phase"
puts

eval_prompt = <<~PROMPT
  You received two research responses on the same topic. Evaluate which is more
  extensive and comprehensive.

  Topic: #{topic}

  == Response A: Claude (claude-sonnet-4-6) ==
  #{anthropic_text}

  == Response B: OpenAI (gpt-5.4) ==
  #{openai_text}

  Evaluate both on these dimensions:
  1. Total length and detail
  2. Breadth of subtopics covered
  3. Depth of analysis
  4. Use of concrete examples
  5. Overall information density

  Provide a clear verdict: which response (A or B) is more extensive, and why?
PROMPT

evaluator = A2A.client(url: EVALUATOR_URL)
puts "Sending both responses to evaluator…"
puts

eval_task     = evaluator.send_task(message: A2A::Models::Message.user(eval_prompt))
eval_artifact = eval_task.artifacts&.first

if eval_artifact
  puts "=== Evaluation ==="
  puts eval_artifact.parts.filter_map(&:text).join
else
  puts "(Evaluator returned no artifact — task state: #{eval_task.status&.state})"
end
