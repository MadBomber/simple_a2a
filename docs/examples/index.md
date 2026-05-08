# Examples

The `examples/` directory contains runnable demo applications that exercise the gem from a client and server process. Each demo uses `examples/common_config.rb`, which adds the repository `lib/` directory to `$LOAD_PATH` before requiring `simple_a2a`, so the examples run against the local checkout.

<svg viewBox="0 0 900 330" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="examples-title examples-desc">
  <title id="examples-title">simple_a2a example applications</title>
  <desc id="examples-desc">Dark themed transparent-background diagram showing the three example applications and the A2A capabilities they demonstrate.</desc>
  <defs>
    <linearGradient id="blue" x1="0" x2="1">
      <stop offset="0" stop-color="#38bdf8"/>
      <stop offset="1" stop-color="#2563eb"/>
    </linearGradient>
    <linearGradient id="green" x1="0" x2="1">
      <stop offset="0" stop-color="#34d399"/>
      <stop offset="1" stop-color="#16a34a"/>
    </linearGradient>
    <linearGradient id="amber" x1="0" x2="1">
      <stop offset="0" stop-color="#fbbf24"/>
      <stop offset="1" stop-color="#f97316"/>
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <g fill="none" stroke="#334155" stroke-width="2">
    <path d="M295 165H365"/>
    <path d="M535 165H605"/>
  </g>
  <g filter="url(#glow)">
    <rect x="45" y="65" width="250" height="200" rx="14" fill="#0f172a" stroke="url(#blue)" stroke-width="2"/>
    <rect x="325" y="65" width="250" height="200" rx="14" fill="#0f172a" stroke="url(#green)" stroke-width="2"/>
    <rect x="605" y="65" width="250" height="200" rx="14" fill="#0f172a" stroke="url(#amber)" stroke-width="2"/>
  </g>
  <g font-family="Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">
    <text x="70" y="108" fill="#e2e8f0" font-size="24" font-weight="700">01 Basic Usage</text>
    <text x="70" y="145" fill="#93c5fd" font-size="16">JSON-RPC request/response</text>
    <text x="70" y="180" fill="#cbd5e1" font-size="15">agent card discovery</text>
    <text x="70" y="205" fill="#cbd5e1" font-size="15">send, list, and get tasks</text>
    <text x="70" y="230" fill="#cbd5e1" font-size="15">client error handling</text>
    <text x="350" y="108" fill="#e2e8f0" font-size="24" font-weight="700">02 Streaming</text>
    <text x="350" y="145" fill="#86efac" font-size="16">SSE task subscription</text>
    <text x="350" y="180" fill="#cbd5e1" font-size="15">working/final statuses</text>
    <text x="350" y="205" fill="#cbd5e1" font-size="15">append artifact chunks</text>
    <text x="350" y="230" fill="#cbd5e1" font-size="15">incremental client output</text>
    <text x="630" y="108" fill="#e2e8f0" font-size="24" font-weight="700">03 LLM Research</text>
    <text x="630" y="145" fill="#fcd34d" font-size="16">multi-agent orchestration</text>
    <text x="630" y="180" fill="#cbd5e1" font-size="15">Anthropic + OpenAI agents</text>
    <text x="630" y="205" fill="#cbd5e1" font-size="15">evaluator agent</text>
    <text x="630" y="230" fill="#cbd5e1" font-size="15">CLI and web clients</text>
  </g>
</svg>

## Run a demo

From the repository root:

```bash
bundle exec ruby examples/run 01_basic_usage
bundle exec ruby examples/run 02_streaming
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
