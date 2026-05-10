# 09 Multipart Artifacts

**Run it:**

```bash
bundle exec ruby examples/run 09_multipart
```

**What it shows:** a single artifact carrying all four `Part` types — `text`, `json`, `binary`, and `url` — and how the client uses predicate methods to dispatch on part type.

---

## Files

| File | Purpose |
|---|---|
| `examples/09_multipart/server.rb` | `ReportExecutor` builds one four-part artifact covering every `Part` constructor |
| `examples/09_multipart/client.rb` | Iterates artifact parts; uses `text?`, `json?`, `raw?`, `url?` to process each type |

---

## The four Part types

| Constructor | Transport format | Client accessor |
|---|---|---|
| `Part.text(str, media_type:)` | Plain string | `part.text` |
| `Part.json(hash, filename:)` | JSON object | `part.data` |
| `Part.binary(bytes, media_type:, filename:)` | Base64-encoded string | `part.decoded_bytes` |
| `Part.from_url(url, media_type:, filename:)` | URL string, no inline content | `part.url` |

---

## Server — `ReportExecutor`

```ruby
def call(ctx)
  topic = ctx.message.text_content.strip

  summary = A2A::Models::Part.text(<<~TEXT, media_type: "text/plain")
    Report on: #{topic}
    Generated at #{Time.now.utc.iso8601}
  TEXT

  metadata = A2A::Models::Part.json(
    { "topic" => topic, "word_count" => topic.split.length, "confidence" => 0.92 },
    filename: "metadata.json"
  )

  csv_bytes = build_csv(topic).b
  csv_part  = A2A::Models::Part.binary(
    csv_bytes, media_type: "text/csv", filename: "term_scores.csv"
  )

  url_part = A2A::Models::Part.from_url(
    "https://en.wikipedia.org/wiki/Special:Search?search=#{URI.encode_uri_component(topic)}",
    media_type: "text/html",
    filename:   "reference.html"
  )

  ctx.task.complete!(artifacts: [
    A2A::Models::Artifact.new(name: "report", parts: [summary, metadata, csv_part, url_part])
  ])
end
```

---

## Client — type-safe dispatch

```ruby
artifact.parts.each do |part|
  if part.text?
    puts part.text

  elsif part.json?
    puts JSON.pretty_generate(part.data)

  elsif part.raw?
    bytes = part.decoded_bytes
    puts "#{bytes.bytesize} bytes (#{part.media_type})"
    puts bytes.force_encoding("UTF-8")

  elsif part.url?
    puts part.url
  end
end
```

The predicates `text?`, `json?`, `raw?`, and `url?` are mutually exclusive. `decoded_bytes` reverses the base64 encoding that the transport layer applies to binary parts.

---

## Protocol coverage

| Spec section | What the demo shows |
|---|---|
| `Part.text` | Plain prose with `media_type: "text/plain"` |
| `Part.json` | Structured data as a Ruby Hash; serialized as a JSON object in the artifact |
| `Part.binary` | Raw bytes base64-encoded for transport; `decoded_bytes` restores the original |
| `Part.from_url` | URL reference with `media_type` and `filename`; no content is inlined |
| `Part` predicates | `text?`, `json?`, `raw?`, `url?` allow type-safe dispatch on the receiving end |
| Multi-part `Artifact` | One artifact contains all four parts; clients can select the representation they need |
| `Artifact.name` | Named artifact (`"report"`) for client-side identification |
