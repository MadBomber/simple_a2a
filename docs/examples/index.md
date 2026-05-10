# Examples

The `examples/` directory contains eleven runnable demo applications that exercise the gem from a client and server process. Each demo uses `examples/common_config.rb`, which adds the repository `lib/` directory to `$LOAD_PATH` before requiring `simple_a2a`, so the examples run against the local checkout.

<svg viewBox="0 0 830 510" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="examples-title examples-desc">
  <title id="examples-title">simple_a2a example applications</title>
  <desc id="examples-desc">Dark themed diagram showing all eleven example applications in a 3×4 grid with the A2A capabilities each demonstrates.</desc>
  <defs>
    <linearGradient id="eg-blue"   x1="0" x2="1"><stop offset="0" stop-color="#38bdf8"/><stop offset="1" stop-color="#2563eb"/></linearGradient>
    <linearGradient id="eg-green"  x1="0" x2="1"><stop offset="0" stop-color="#34d399"/><stop offset="1" stop-color="#16a34a"/></linearGradient>
    <linearGradient id="eg-amber"  x1="0" x2="1"><stop offset="0" stop-color="#fbbf24"/><stop offset="1" stop-color="#f97316"/></linearGradient>
    <linearGradient id="eg-violet" x1="0" x2="1"><stop offset="0" stop-color="#a78bfa"/><stop offset="1" stop-color="#7c3aed"/></linearGradient>
    <linearGradient id="eg-teal"   x1="0" x2="1"><stop offset="0" stop-color="#2dd4bf"/><stop offset="1" stop-color="#0891b2"/></linearGradient>
    <linearGradient id="eg-rose"   x1="0" x2="1"><stop offset="0" stop-color="#fb7185"/><stop offset="1" stop-color="#e11d48"/></linearGradient>
    <filter id="eg-glow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000" flood-opacity="0.35"/>
    </filter>
  </defs>

  <!-- Row 0 -->
  <g filter="url(#eg-glow)">
    <rect x="15"  y="15"  width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-blue)"   stroke-width="2"/>
    <rect x="285" y="15"  width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-green)"  stroke-width="2"/>
    <rect x="555" y="15"  width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-amber)"  stroke-width="2"/>
  </g>
  <!-- Row 1 -->
  <g filter="url(#eg-glow)">
    <rect x="15"  y="135" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-blue)"   stroke-width="2"/>
    <rect x="285" y="135" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-amber)"  stroke-width="2"/>
    <rect x="555" y="135" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-green)"  stroke-width="2"/>
  </g>
  <!-- Row 2 -->
  <g filter="url(#eg-glow)">
    <rect x="15"  y="255" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-violet)" stroke-width="2"/>
    <rect x="285" y="255" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-amber)"  stroke-width="2"/>
    <rect x="555" y="255" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-teal)"   stroke-width="2"/>
  </g>
  <!-- Row 3 -->
  <g filter="url(#eg-glow)">
    <rect x="15"  y="375" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-rose)"   stroke-width="2"/>
    <rect x="285" y="375" width="260" height="110" rx="10" fill="#0f172a" stroke="url(#eg-violet)" stroke-width="2"/>
  </g>

  <g font-family="Inter, ui-sans-serif, system-ui, sans-serif">
    <!-- 01 Basic Usage -->
    <text x="30"  y="47"  fill="#e2e8f0" font-size="17" font-weight="700">01 Basic Usage</text>
    <text x="30"  y="67"  fill="#93c5fd" font-size="12">JSON-RPC request/response</text>
    <text x="30"  y="85"  fill="#cbd5e1" font-size="12">agent card discovery</text>
    <text x="30"  y="103" fill="#cbd5e1" font-size="12">tasks/send · get · list · errors</text>

    <!-- 02 Streaming -->
    <text x="300" y="47"  fill="#e2e8f0" font-size="17" font-weight="700">02 Streaming</text>
    <text x="300" y="67"  fill="#86efac" font-size="12">tasks/sendSubscribe · SSE</text>
    <text x="300" y="85"  fill="#cbd5e1" font-size="12">working / completed status</text>
    <text x="300" y="103" fill="#cbd5e1" font-size="12">incremental artifact chunks</text>

    <!-- 03 LLM Research -->
    <text x="570" y="47"  fill="#e2e8f0" font-size="17" font-weight="700">03 LLM Research</text>
    <text x="570" y="67"  fill="#fcd34d" font-size="12">multi-agent · multi_server</text>
    <text x="570" y="85"  fill="#cbd5e1" font-size="12">parallel SSE · evaluator</text>
    <text x="570" y="103" fill="#cbd5e1" font-size="12">CLI + Sinatra web client</text>

    <!-- 04 Resubscribe -->
    <text x="30"  y="167" fill="#e2e8f0" font-size="17" font-weight="700">04 Resubscribe</text>
    <text x="30"  y="187" fill="#93c5fd" font-size="12">tasks/resubscribe</text>
    <text x="30"  y="205" fill="#cbd5e1" font-size="12">mid-stream join · snapshot</text>
    <text x="30"  y="223" fill="#cbd5e1" font-size="12">concurrent subscribers</text>

    <!-- 05 Cancellation -->
    <text x="300" y="167" fill="#e2e8f0" font-size="17" font-weight="700">05 Cancellation</text>
    <text x="300" y="187" fill="#fcd34d" font-size="12">tasks/cancel</text>
    <text x="300" y="205" fill="#cbd5e1" font-size="12">concurrent tasks · lifecycle</text>
    <text x="300" y="223" fill="#cbd5e1" font-size="12">cooperative cancellation</text>

    <!-- 06 Push Notifications -->
    <text x="570" y="167" fill="#e2e8f0" font-size="17" font-weight="700">06 Push Notifications</text>
    <text x="570" y="187" fill="#86efac" font-size="12">pushNotification/set/get/del</text>
    <text x="570" y="205" fill="#cbd5e1" font-size="12">webhook delivery · PushSender</text>
    <text x="570" y="223" fill="#cbd5e1" font-size="12">out-of-band events</text>

    <!-- 07 Agent Chaining -->
    <text x="30"  y="287" fill="#e2e8f0" font-size="17" font-weight="700">07 Agent Chaining</text>
    <text x="30"  y="307" fill="#c4b5fd" font-size="12">A2A.client inside executor</text>
    <text x="30"  y="325" fill="#cbd5e1" font-size="12">agent-to-agent delegation</text>
    <text x="30"  y="343" fill="#cbd5e1" font-size="12">composable pipelines</text>

    <!-- 08 Interrupted States -->
    <text x="300" y="287" fill="#e2e8f0" font-size="17" font-weight="700">08 Interrupted States</text>
    <text x="300" y="307" fill="#fcd34d" font-size="12">input_required · auth_required</text>
    <text x="300" y="325" fill="#cbd5e1" font-size="12">multi-turn conversations</text>
    <text x="300" y="343" fill="#cbd5e1" font-size="12">message context_id threading</text>

    <!-- 09 Multipart -->
    <text x="570" y="287" fill="#e2e8f0" font-size="17" font-weight="700">09 Multipart</text>
    <text x="570" y="307" fill="#5eead4" font-size="12">text · json · binary · url</text>
    <text x="570" y="325" fill="#cbd5e1" font-size="12">Part predicates · base64</text>
    <text x="570" y="343" fill="#cbd5e1" font-size="12">multi-type artifact</text>

    <!-- 10 Auth Headers -->
    <text x="30"  y="407" fill="#e2e8f0" font-size="17" font-weight="700">10 Auth Headers</text>
    <text x="30"  y="427" fill="#fda4af" font-size="12">A2A.client(headers:)</text>
    <text x="30"  y="445" fill="#cbd5e1" font-size="12">Bearer token middleware</text>
    <text x="30"  y="463" fill="#cbd5e1" font-size="12">Rack middleware composition</text>

    <!-- 11 SQLite Storage -->
    <text x="300" y="407" fill="#e2e8f0" font-size="17" font-weight="700">11 SQLite Storage</text>
    <text x="300" y="427" fill="#c4b5fd" font-size="12">Storage::Base injection</text>
    <text x="300" y="445" fill="#cbd5e1" font-size="12">WAL persistence · Brewfile</text>
    <text x="300" y="463" fill="#cbd5e1" font-size="12">cross-restart task survival</text>
  </g>
</svg>

## Run a demo

From the repository root:

```bash
bundle exec ruby examples/run 01_basic_usage
bundle exec ruby examples/run 05_cancellation
bundle exec ruby examples/run 11_sqlite_storage
```

The launcher starts the demo server on `http://localhost:9292`, waits for it to accept connections, runs the demo client, and then shuts the server down.

To run a demo manually, start its `server.rb` in one terminal and its `client.rb` in another:

```bash
bundle exec ruby examples/01_basic_usage/server.rb
bundle exec ruby examples/01_basic_usage/client.rb
```

Some demos (`03_llm_research`, `11_sqlite_storage`) have custom `run` scripts that manage a more complex lifecycle; the top-level launcher detects and delegates to them automatically.

## Demo-specific dependencies

Most demos run with the gem's standard development setup (`bundle install`).

**Demo 03 — LLM Research** requires LLM provider API keys and additional gems not in the gem's runtime dependency list:

```bash
bundle add ruby_llm async-http-faraday sinatra
export ANTHROPIC_API_KEY=your_key_here
export OPENAI_API_KEY=your_key_here
bundle exec ruby examples/run 03_llm_research
```

**Demo 11 — SQLite Storage** has its own `Gemfile` and `Brewfile`. The `run` script installs the sqlite3 binary (via Homebrew on macOS) and runs `bundle install` with the local Gemfile before starting the server. No manual setup is required.

## Demo index

| # | Demo | Run command | Documentation |
|---|---|---|---|
| 01 | Basic Usage | `examples/run 01_basic_usage` | [Basic Usage](basic-usage.md) |
| 02 | Streaming | `examples/run 02_streaming` | [Streaming](streaming.md) |
| 03 | LLM Research | `examples/run 03_llm_research` | [LLM Research](llm-research.md) |
| 04 | Resubscribe | `examples/run 04_resubscribe` | [Resubscribe](resubscribe.md) |
| 05 | Cancellation | `examples/run 05_cancellation` | [Cancellation](cancellation.md) |
| 06 | Push Notifications | `examples/run 06_push_notifications` | [Push Notifications](push-notifications.md) |
| 07 | Agent Chaining | `examples/run 07_agent_chaining` | [Agent Chaining](agent-chaining.md) |
| 08 | Interrupted States | `examples/run 08_interrupted_states` | [Interrupted States](interrupted-states.md) |
| 09 | Multipart Artifacts | `examples/run 09_multipart` | [Multipart](multipart.md) |
| 10 | Auth Headers | `examples/run 10_auth_headers` | [Auth Headers](auth-headers.md) |
| 11 | SQLite Storage | `examples/run 11_sqlite_storage` | [SQLite Storage](sqlite-storage.md) |
