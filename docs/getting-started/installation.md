# Installation

## Requirements

- Ruby 3.2 or higher (tested on Ruby 4.0)
- Bundler 2.x

## Gemfile

```ruby
gem "simple_a2a"
```

Then run:

```bash
bundle install
```

## Direct install

```bash
gem install simple_a2a
```

## Dependencies

`simple_a2a` pulls in the following gems automatically:

| Gem | Purpose |
|---|---|
| `async` | Async fiber runtime |
| `async-http` | Non-blocking HTTP client (used by `Client::Base` and `Client::SSE`) |
| `falcon` | Async-native Rack HTTP server |
| `roda` | Rack router for the server endpoint |
| `rack` | WSGI-style Ruby web interface |
| `zeitwerk` | Autoloading |
| `jwt` | RS256 JWT signing for push notification webhooks |
| `logger` | Ruby standard logger (bundled gem in Ruby 4.0+) |
| `simple_flow` | Pipeline composition for executor chains |
| `typed_bus` | Per-task SSE event fan-out |

## Verifying the install

```ruby
require "simple_a2a"
puts A2A::VERSION   # => "0.1.0"
```
