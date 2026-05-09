# Examples

The `examples/` directory contains runnable demo applications that exercise the gem from a client and server process. Each demo uses `examples/common_config.rb`, which adds the repository `lib/` directory to `$LOAD_PATH` before requiring `simple_a2a`, so the examples run against the local checkout.

<svg viewBox="0 0 640 440" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="examples-title examples-desc">
  <title id="examples-title">simple_a2a example applications</title>
  <desc id="examples-desc">Dark themed transparent-background diagram showing the four example applications in a 2x2 grid and the A2A capabilities each demonstrates.</desc>
  <defs>
    <linearGradient id="eg-blue" x1="0" x2="1"><stop offset="0" stop-color="#38bdf8"/><stop offset="1" stop-color="#2563eb"/></linearGradient>
    <linearGradient id="eg-green" x1="0" x2="1"><stop offset="0" stop-color="#34d399"/><stop offset="1" stop-color="#16a34a"/></linearGradient>
    <linearGradient id="eg-amber" x1="0" x2="1"><stop offset="0" stop-color="#fbbf24"/><stop offset="1" stop-color="#f97316"/></linearGradient>
    <linearGradient id="eg-violet" x1="0" x2="1"><stop offset="0" stop-color="#a78bfa"/><stop offset="1" stop-color="#7c3aed"/></linearGradient>
    <filter id="eg-glow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#000" flood-opacity="0.4"/>
    </filter>
  </defs>
  <g filter="url(#eg-glow)">
    <rect x="20"  y="20"  width="280" height="190" rx="14" fill="#0f172a" stroke="url(#eg-blue)"   stroke-width="2"/>
    <rect x="340" y="20"  width="280" height="190" rx="14" fill="#0f172a" stroke="url(#eg-green)"  stroke-width="2"/>
    <rect x="20"  y="240" width="280" height="190" rx="14" fill="#0f172a" stroke="url(#eg-amber)"  stroke-width="2"/>
    <rect x="340" y="240" width="280" height="190" rx="14" fill="#0f172a" stroke="url(#eg-violet)" stroke-width="2"/>
  </g>
  <g font-family="Inter, ui-sans-serif, system-ui, sans-serif">
    <text x="44"  y="62"  fill="#e2e8f0" font-size="20" font-weight="700">01 Basic Usage</text>
    <text x="44"  y="92"  fill="#93c5fd" font-size="14">JSON-RPC request/response</text>
    <text x="44"  y="120" fill="#cbd5e1" font-size="13">agent card discovery</text>
    <text x="44"  y="143" fill="#cbd5e1" font-size="13">send, list, and get tasks</text>
    <text x="44"  y="166" fill="#cbd5e1" font-size="13">client error handling</text>

    <text x="364" y="62"  fill="#e2e8f0" font-size="20" font-weight="700">02 Streaming</text>
    <text x="364" y="92"  fill="#86efac" font-size="14">SSE task subscription</text>
    <text x="364" y="120" fill="#cbd5e1" font-size="13">working / final statuses</text>
    <text x="364" y="143" fill="#cbd5e1" font-size="13">append artifact chunks</text>
    <text x="364" y="166" fill="#cbd5e1" font-size="13">incremental client output</text>

    <text x="44"  y="282" fill="#e2e8f0" font-size="20" font-weight="700">03 LLM Research</text>
    <text x="44"  y="312" fill="#fcd34d" font-size="14">multi-agent orchestration</text>
    <text x="44"  y="340" fill="#cbd5e1" font-size="13">Anthropic + OpenAI agents</text>
    <text x="44"  y="363" fill="#cbd5e1" font-size="13">evaluator agent</text>
    <text x="44"  y="386" fill="#cbd5e1" font-size="13">CLI and web clients</text>

    <text x="364" y="282" fill="#e2e8f0" font-size="20" font-weight="700">04 Resubscribe</text>
    <text x="364" y="312" fill="#c4b5fd" font-size="14">tasks/resubscribe</text>
    <text x="364" y="340" fill="#cbd5e1" font-size="13">concurrent SSE subscribers</text>
    <text x="364" y="363" fill="#cbd5e1" font-size="13">live task snapshot on join</text>
    <text x="364" y="386" fill="#cbd5e1" font-size="13">RactorQueue fan-out</text>
  </g>
</svg>

## Run a demo

From the repository root:

```bash
bundle exec ruby examples/run 01_basic_usage
bundle exec ruby examples/run 02_streaming
bundle exec ruby examples/run 04_resubscribe
```

The launcher starts the demo server on `http://localhost:9292`, waits for it to accept connections, runs the demo client, and then shuts the server down.

To run a demo manually, start its `server.rb` in one terminal and its `client.rb` in another:

```bash
bundle exec ruby examples/01_basic_usage/server.rb
bundle exec ruby examples/01_basic_usage/client.rb
```

## Demo-specific dependencies

The basic and streaming demos use only the gem and its normal development setup. The LLM research demo intentionally keeps its LLM and web UI dependencies out of the gem runtime dependency list. Install the demo-specific gems before running it:

```bash
bundle add ruby_llm async-http-faraday sinatra
```

Then set API keys:

```bash
export ANTHROPIC_API_KEY=your_key_here
export OPENAI_API_KEY=your_key_here
```

## Demo index

| Demo | Command | Documentation |
|---|---|---|
| Basic Usage | `bundle exec ruby examples/run 01_basic_usage` | [Basic Usage](basic-usage.md) |
| Streaming | `bundle exec ruby examples/run 02_streaming` | [Streaming](streaming.md) |
| Multi-Agent LLM Research | `bundle exec ruby examples/run 03_llm_research` | [Multi-Agent LLM Research](llm-research.md) |
| Resubscribe | `bundle exec ruby examples/run 04_resubscribe` | [Resubscribe](resubscribe.md) |
