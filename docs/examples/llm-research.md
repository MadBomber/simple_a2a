# Multi-Agent LLM Research Demo

`examples/03_llm_research` demonstrates a multi-agent A2A server with two streaming research agents and one evaluator agent. It includes both a CLI client and a Sinatra web client.

## What it runs

| Path | Agent | Model |
|---|---|---|
| `http://localhost:9292/anthropic` | `AnthropicResearchAgent` | `claude-sonnet-4-6` |
| `http://localhost:9292/openai` | `OpenAIResearchAgent` | `gpt-5.4` |
| `http://localhost:9292/evaluator` | `EvaluatorAgent` | `claude-sonnet-4-6` |
| `http://localhost:4567` | Sinatra web UI | Streams both responses and the evaluation to the browser |

## Files

| File | Purpose |
|---|---|
| `examples/03_llm_research/server.rb` | Configures RubyLLM, defines three executors, and starts a path-routed multi-agent A2A server |
| `examples/03_llm_research/client.rb` | CLI client that queries both research agents in parallel and sends both responses to the evaluator |
| `examples/03_llm_research/web_client.rb` | Sinatra UI that streams both research responses and the evaluator response to the browser |
| `examples/03_llm_research/run` | Lifecycle script that starts the A2A server and web client together |

## Setup

The demo uses LLM and web UI libraries that are intentionally not runtime dependencies of the `simple_a2a` gem. Add them to your local bundle before running the demo:

```bash
bundle add ruby_llm async-http-faraday sinatra
```

Set both provider keys:

```bash
export ANTHROPIC_API_KEY=your_key_here
export OPENAI_API_KEY=your_key_here
```

## Run the web demo

From the repository root:

```bash
bundle exec ruby examples/run 03_llm_research
```

The custom runner starts:

| Service | URL |
|---|---|
| A2A multi-agent server | `http://localhost:9292` |
| Web client | `http://localhost:4567` |

Open `http://localhost:4567`, enter a topic, and the page streams output from both research agents followed by the evaluator.

## Run the CLI client

Start the multi-agent server:

```bash
bundle exec ruby examples/03_llm_research/server.rb
```

Then run the CLI client from another terminal:

```bash
bundle exec ruby examples/03_llm_research/client.rb "compare the practical tradeoffs of A2A and MCP"
```

If no topic is supplied, the client uses its built-in default topic.

## Server design

The server uses `A2A.multi_server` to mount multiple agents under one Falcon process:

```ruby
A2A.multi_server(
  agents: {
    "/anthropic" => { agent_card: anthropic_card, executor: AnthropicResearchExecutor.new },
    "/openai"    => { agent_card: openai_card,    executor: OpenAIResearchExecutor.new },
    "/evaluator" => { agent_card: evaluator_card, executor: EvaluatorExecutor.new }
  },
  port: 9292
).run
```

Each executor includes a shared streaming helper that calls RubyLLM and emits `TaskArtifactUpdateEvent` chunks while the model response arrives.

## Web client design

The web client exposes a browser-facing SSE endpoint at `/research`. Internally it opens A2A SSE subscriptions to the Anthropic and OpenAI agents in parallel, buffers both complete responses, then streams the evaluator response back to the browser.

This is useful as a reference for bridging A2A streaming into another application protocol while keeping the A2A agents independently addressable.
