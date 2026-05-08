#!/usr/bin/env ruby
# frozen_string_literal: true

# Sinatra web UI for the A2A multi-agent research demo.
#
# Usage (via lifecycle script):
#   ruby examples/run 03_llm_research
#
# Usage (manually):
#   bundle exec ruby examples/03_llm_research/server.rb &
#   bundle exec ruby examples/03_llm_research/web_client.rb
#   open http://localhost:4567

require_relative "../common_config"
require "sinatra/base"
require "async/queue"
require "json"

A2A_BASE      = "http://localhost:9292"
ANTHROPIC_URL = "#{A2A_BASE}/anthropic"
OPENAI_URL    = "#{A2A_BASE}/openai"
EVALUATOR_URL = "#{A2A_BASE}/evaluator"

# ---------------------------------------------------------------------------
# SSE response body.
#
# Protocol::Rack (Falcon's Rack adapter) wraps the body in its own plain Ruby
# fiber and calls body.each from there — Async::Task.current is unavailable
# in that fiber regardless of how we define each.
#
# Bridge with IO.pipe instead:
#   Writer side  — a Thread running its own Async reactor; it calls both A2A
#                  SSE clients in parallel, then the evaluator, and writes
#                  complete "data: …\n\n" strings to the write end.
#   Reader side  — the each body calls gets("\n\n") on the read end.
#                  Inside Falcon's thread the Ruby fiber scheduler intercepts
#                  that blocking read and turns it into a non-blocking await,
#                  so Falcon can serve other requests while we wait.
# ---------------------------------------------------------------------------
class ResearchSSEBody
  def initialize(topic:)
    @topic = topic
  end

  def each
    topic    = @topic
    read_io, write_io = IO.pipe

    producer = Thread.new do
      anthropic_buf = +""
      openai_buf    = +""

      begin
        Async do |task|
          queue = Async::Queue.new

          task_a = task.async do
            A2A.sse_client(url: ANTHROPIC_URL).send_subscribe(
              message: A2A::Models::Message.user(topic)
            ) do |event|
              next unless event.is_a?(A2A::Models::TaskArtifactUpdateEvent)
              text = event.artifact.parts.filter_map(&:text).join
              anthropic_buf << text
              queue.enqueue(agent: "anthropic", text: text)
            end
          rescue => e
            queue.enqueue(agent: "error", text: "Anthropic: #{e.message}")
          ensure
            queue.enqueue(:anthropic_done)
          end

          task_b = task.async do
            A2A.sse_client(url: OPENAI_URL).send_subscribe(
              message: A2A::Models::Message.user(topic)
            ) do |event|
              next unless event.is_a?(A2A::Models::TaskArtifactUpdateEvent)
              text = event.artifact.parts.filter_map(&:text).join
              openai_buf << text
              queue.enqueue(agent: "openai", text: text)
            end
          rescue => e
            queue.enqueue(agent: "error", text: "OpenAI: #{e.message}")
          ensure
            queue.enqueue(:openai_done)
          end

          done_count = 0
          while done_count < 2
            item = queue.dequeue
            case item
            when :anthropic_done, :openai_done
              done_count += 1
            else
              write_io.write("data: #{JSON.generate(item)}\n\n")
            end
          end

          task_a.wait rescue nil
          task_b.wait rescue nil

          write_io.write("data: #{JSON.generate(agent: 'status', text: 'Both agents complete. Evaluating…')}\n\n")

          begin
            A2A.sse_client(url: EVALUATOR_URL).send_subscribe(
              message: A2A::Models::Message.user(eval_prompt(topic, anthropic_buf, openai_buf))
            ) do |event|
              next unless event.is_a?(A2A::Models::TaskArtifactUpdateEvent)
              write_io.write("data: #{JSON.generate(agent: 'evaluator', text: event.artifact.parts.filter_map(&:text).join)}\n\n")
            end
          rescue => e
            write_io.write("data: #{JSON.generate(agent: 'error', text: "Evaluator: #{e.message}")}\n\n")
          end

          write_io.write("data: #{JSON.generate(agent: 'done', text: '')}\n\n")
        end
      rescue => e
        write_io.write("data: #{JSON.generate(agent: 'error', text: e.message)}\n\n") rescue nil
      ensure
        write_io.close rescue nil
      end
    end

    while (line = read_io.gets("\n\n"))
      yield line
    end
  ensure
    read_io.close rescue nil
    producer&.join
  end

  private

  def eval_prompt(topic, a_text, b_text)
    <<~PROMPT
      Two AI agents researched the same topic. Evaluate which response is more extensive and comprehensive.

      Topic: #{topic}

      == Response A: Claude (claude-sonnet-4-6) ==
      #{a_text}

      == Response B: OpenAI (gpt-5.4) ==
      #{b_text}

      Evaluate on: length and detail, breadth of subtopics, depth of analysis, concrete examples, overall information density.
      Give a clear verdict stating which response (A or B) is more extensive, and explain why.
    PROMPT
  end
end

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
class ResearchApp < Sinatra::Base
  set :server,  "falcon"
  set :port,    4567
  set :bind,    "localhost"
  set :logging, false

  get "/" do
    content_type "text/html"
    HTML_PAGE
  end

  get "/research" do
    topic = params[:topic].to_s.strip

    headers "Content-Type"      => "text/event-stream",
            "Cache-Control"     => "no-cache",
            "X-Accel-Buffering" => "no"

    if topic.empty?
      return body ["data: #{JSON.generate(agent: 'error', text: 'Topic is required')}\n\n",
                   "data: #{JSON.generate(agent: 'done',  text: '')}\n\n"]
    end

    body ResearchSSEBody.new(topic: topic)
  end
end

# ---------------------------------------------------------------------------
# HTML (embedded — no views/ directory needed)
# ---------------------------------------------------------------------------
HTML_PAGE = <<~'HTML'
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>A2A Multi-Agent Research</title>
    <style>
      *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

      :root {
        --bg:       #0d1117;
        --surface:  #161b22;
        --surface2: #1c2128;
        --border:   #30363d;
        --text:     #e6edf3;
        --muted:    #8b949e;
        --accent:   #58a6ff;
        --green:    #3fb950;
        --amber:    #d29922;
        --code:     #c9d1d9;
      }

      body {
        background: var(--bg);
        color: var(--text);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        min-height: 100vh;
        padding: 1.5rem;
        display: flex;
        flex-direction: column;
        gap: 1.1rem;
      }

      header { text-align: center; }
      header h1 {
        font-size: 1.5rem;
        font-weight: 600;
        color: var(--accent);
        letter-spacing: -0.02em;
      }
      header p { color: var(--muted); font-size: 0.8rem; margin-top: 0.2rem; }

      .search-row { display: flex; gap: 0.6rem; }

      #topic {
        flex: 1;
        padding: 0.6rem 0.9rem;
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 8px;
        color: var(--text);
        font-size: 0.9rem;
      }
      #topic:focus { outline: none; border-color: var(--accent); }

      #btn {
        padding: 0.6rem 1.3rem;
        background: #238636;
        border: 1px solid rgba(240,246,252,0.1);
        border-radius: 8px;
        color: #fff;
        font-size: 0.9rem;
        font-weight: 500;
        cursor: pointer;
        white-space: nowrap;
      }
      #btn:hover:not(:disabled) { background: #2ea043; }
      #btn:disabled { background: var(--surface2); color: var(--muted); cursor: not-allowed; }

      #status {
        font-size: 0.78rem;
        color: var(--muted);
        text-align: center;
        min-height: 1em;
        font-style: italic;
        border-radius: 6px;
        padding: 0.1rem 0;
        transition: all 0.15s ease;
      }
      #status.error {
        background: #b91c1c;
        color: #fff;
        font-size: 1.15rem;
        font-weight: 700;
        font-style: normal;
        padding: 0.6rem 1rem;
        letter-spacing: 0.01em;
      }

      .panels {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 1rem;
      }

      .panel, .eval-panel {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 10px;
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }

      .panel-header, .eval-header {
        padding: 0.55rem 0.9rem;
        background: var(--surface2);
        border-bottom: 1px solid var(--border);
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex-shrink: 0;
      }

      .dot {
        width: 7px; height: 7px;
        border-radius: 50%;
        background: var(--border);
        flex-shrink: 0;
      }
      .dot.active {
        background: var(--green);
        animation: pulse 1.2s ease-in-out infinite;
      }
      .dot.eval.active { background: var(--amber); }
      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50%       { opacity: 0.35; }
      }

      .panel-title { font-size: 0.82rem; font-weight: 500; }
      .panel-model {
        font-size: 0.7rem;
        color: var(--accent);
        font-family: monospace;
        margin-left: auto;
      }
      .panel-model.eval-model { color: var(--amber); }
      .char-count {
        font-size: 0.68rem;
        color: var(--muted);
        font-variant-numeric: tabular-nums;
        margin-left: 0.4rem;
      }

      .panel-body {
        flex: 1;
        padding: 0.75rem 0.9rem;
        font-family: "SFMono-Regular", "Consolas", "Liberation Mono", monospace;
        font-size: 0.78rem;
        line-height: 1.65;
        white-space: pre-wrap;
        word-break: break-word;
        overflow-y: auto;
        color: var(--code);
        height: 380px;
      }
      .panel-body.placeholder, .eval-body.placeholder {
        color: var(--muted);
        font-family: sans-serif;
        font-size: 0.8rem;
        font-style: italic;
      }

      .eval-body {
        padding: 0.75rem 0.9rem;
        font-family: "SFMono-Regular", "Consolas", "Liberation Mono", monospace;
        font-size: 0.78rem;
        line-height: 1.65;
        white-space: pre-wrap;
        word-break: break-word;
        color: var(--code);
        min-height: 100px;
      }
    </style>
  </head>
  <body>
    <header>
      <h1>A2A Multi-Agent Research</h1>
      <p>Two LLMs research the same topic in parallel · a third evaluates the results</p>
    </header>

    <div class="search-row">
      <input id="topic" type="text"
        placeholder="Enter a research topic…"
        value="shortcomings and criticisms of the A2A protocol specification">
      <button id="btn" onclick="go()">Research</button>
    </div>

    <div id="status"></div>

    <div class="panels">
      <div class="panel">
        <div class="panel-header">
          <div class="dot" id="dot-a"></div>
          <span class="panel-title">Anthropic</span>
          <span class="panel-model">claude-sonnet-4-6</span>
          <span class="char-count" id="cnt-a"></span>
        </div>
        <div class="panel-body placeholder" id="out-a">Waiting for response…</div>
      </div>

      <div class="panel">
        <div class="panel-header">
          <div class="dot" id="dot-b"></div>
          <span class="panel-title">OpenAI</span>
          <span class="panel-model">gpt-5.4</span>
          <span class="char-count" id="cnt-b"></span>
        </div>
        <div class="panel-body placeholder" id="out-b">Waiting for response…</div>
      </div>
    </div>

    <div class="eval-panel">
      <div class="eval-header">
        <div class="dot eval" id="dot-e"></div>
        <span class="panel-title">Evaluation</span>
        <span class="panel-model eval-model">claude-sonnet-4-6</span>
      </div>
      <div class="eval-body placeholder" id="out-e">Evaluation will appear here after both agents complete.</div>
    </div>

    <script>
      let src = null;
      const lenA = { n: 0 }, lenB = { n: 0 };

      function status(msg, isError) {
        const el = document.getElementById('status');
        el.textContent = msg;
        el.classList.toggle('error', !!isError);
      }
      function dot(id, on)  { document.getElementById(id).classList.toggle('active', on); }

      function append(elId, text, cntId, len) {
        const el = document.getElementById(elId);
        if (el.classList.contains('placeholder')) {
          el.classList.remove('placeholder');
          el.textContent = '';
        }
        el.textContent += text;
        el.scrollTop = el.scrollHeight;
        if (cntId) {
          len.n += text.length;
          document.getElementById(cntId).textContent = len.n.toLocaleString() + ' chars';
        }
      }

      function reset() {
        ['out-a','out-b','out-e'].forEach(id => {
          const el = document.getElementById(id);
          el.textContent = id === 'out-e'
            ? 'Evaluation will appear here after both agents complete.'
            : 'Waiting for response…';
          el.classList.add('placeholder');
        });
        ['dot-a','dot-b','dot-e'].forEach(id => dot(id, false));
        ['cnt-a','cnt-b'].forEach(id => document.getElementById(id).textContent = '');
        lenA.n = 0; lenB.n = 0;
      }

      function go() {
        const topic = document.getElementById('topic').value.trim();
        if (!topic) return;

        if (src) { src.close(); src = null; }
        reset();
        document.getElementById('btn').disabled = true;
        dot('dot-a', true); dot('dot-b', true);
        status('Querying both agents in parallel…', false);

        src = new EventSource('/research?topic=' + encodeURIComponent(topic));

        src.onmessage = e => {
          const { agent, text } = JSON.parse(e.data);
          switch (agent) {
            case 'anthropic': append('out-a', text, 'cnt-a', lenA); break;
            case 'openai':    append('out-b', text, 'cnt-b', lenB); break;
            case 'evaluator': append('out-e', text); break;
            case 'status':
              status(text);
              if (text.includes('Evaluat')) {
                dot('dot-a', false); dot('dot-b', false); dot('dot-e', true);
              }
              break;
            case 'done':
              dot('dot-e', false);
              status('Research complete.');
              document.getElementById('btn').disabled = false;
              src.close(); src = null;
              break;
            case 'error':
              status('Error: ' + text, true);
              document.getElementById('btn').disabled = false;
              ['dot-a','dot-b','dot-e'].forEach(id => dot(id, false));
              src.close(); src = null;
              break;
          }
        };

        src.onerror = () => {
          if (!src || src.readyState === EventSource.CLOSED) return;
          status('Connection lost.', true);
          document.getElementById('btn').disabled = false;
          ['dot-a','dot-b','dot-e'].forEach(id => dot(id, false));
          src.close(); src = null;
        };
      }

      document.getElementById('topic').addEventListener('keydown', e => {
        if (e.key === 'Enter') go();
      });
    </script>
  </body>
  </html>
HTML

ResearchApp.run!
