## [Unreleased]

### Added

- `tasks/resubscribe` — attach an SSE stream to an existing running task (A2A `SubscribeToTask`
  operation). The first event is the current Task snapshot (spec requirement); subsequent events
  mirror those emitted by the executor in real time.
- `Client::SSE#resubscribe(task_id:, &block)` — client-side counterpart for `tasks/resubscribe`.
- `Server::TaskBroadcast` — lock-free, fiber-scheduler-aware fan-out broadcaster. Replaces the
  anonymous streaming router and `EventRouter`. Each running task gets one broadcast; each SSE
  subscriber (original or resubscribed) gets its own `RactorQueue`.
- `Server::BroadcastRegistry` — thread-safe `task_id → TaskBroadcast` map held at the App class
  level. Allows `tasks/resubscribe` and `tasks/cancel` to locate a live broadcast.
- `tasks/pushNotification/set|get|delete|list` — push notification config CRUD now fully
  implemented. Configs are stored per task ID in a new `Server::PushConfigStore`; `set` validates
  the task exists and that `webhookUrl` is present before storing.
- `Server::PushConfigStore` — thread-safe in-memory store for `PushNotificationConfig` objects,
  keyed by task ID. One instance is created per `Server::App` automatically.
- `examples/04_resubscribe` — two concurrent SSE subscribers demonstrating snapshot-on-join,
  independent fan-out, and single-completion guarantees.
- `examples/05_cancellation` — three concurrent `tasks/sendSubscribe` streams; one task is
  cancelled mid-flight while the others complete normally.
- `examples/06_push_notifications` — full push notification lifecycle: submit task, register
  webhook, receive out-of-band HTTP POSTs per step, then get/list/delete the config with no
  open SSE connection required.
- `examples/07_agent_chaining` — three agents (`ReverseAgent`, `ShoutAgent`, `PipelineAgent`)
  on one port via `A2A.multi_server`; the pipeline executor chains to the other two agents over
  the protocol, invisible to the client.
- `examples/08_interrupted_states` — `input_required` and `auth_required` interrupted states
  demonstrated with `OrderAgent` (pauses for user input) and `VaultAgent` (blocks on wrong
  token); each follow-up turn is a separate `tasks/send` threaded by `message.context_id`.
- `examples/09_multipart` — all four `Part` types in one artifact: text summary, JSON metadata,
  base64-encoded binary CSV, and URL reference; client uses `text?/json?/raw?/url?` predicates.
- `examples/10_auth_headers` — `headers:` option on `A2A.client` with a Bearer token middleware;
  agent card discovery is public while RPC calls require `Authorization: Bearer <token>`.
- `examples/11_sqlite_storage` — persistent task storage across server restarts via
  `SqliteStorage < A2A::Storage::Base` (WAL mode, mutex, JSON blobs); Brewfile + Gemfile pattern
  keeps SQLite dependency out of the main gem.
- MkDocs documentation pages for examples 05–11 (`cancellation`, `push-notifications`,
  `agent-chaining`, `interrupted-states`, `multipart`, `auth-headers`, `sqlite-storage`).
- `compare_agent2agent.md` — side-by-side comparison of A2A protocol operations at the repo root.

### Changed

- `handle_cancel` now routes cancellation events through the live broadcast so SSE subscribers
  observe the `canceled` state update in real time.
- `Server::Base` and `Server::MultiAgent` no longer create an `EventRouter`; they inject a fresh
  `BroadcastRegistry` into each App subclass instead.
- `Server::Base` now accepts a `push_config_store:` keyword so the executor and the App share
  the same store instance (fixes injection gap).
- README Examples section expanded to an 11-row table; `docs/examples/index.md` rebuilt with
  a 3×4 SVG grid covering all demos.

### Fixed

- Removed phantom `simple_flow` runtime dependency from gemspec.
- Added missing `digest` require (fixes JWT signing in push notification delivery).

### Removed

- `Server::EventRouter` and its `TypedBus`-based pub/sub — superseded by `TaskBroadcast`.
- `typed_bus` runtime dependency — removed entirely.

### Dependencies

- Added `ractor_queue ~> 0.2` runtime dependency (replaces `typed_bus`).

## [0.1.0] - 2026-05-07

- Initial release
