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

### Changed

- `handle_cancel` now routes cancellation events through the live broadcast so SSE subscribers
  observe the `canceled` state update in real time.
- `Server::Base` and `Server::MultiAgent` no longer create an `EventRouter`; they inject a fresh
  `BroadcastRegistry` into each App subclass instead.

### Removed

- `Server::EventRouter` and its `TypedBus`-based pub/sub — superseded by `TaskBroadcast`.
- `typed_bus` runtime dependency — removed entirely.

### Dependencies

- Added `ractor_queue ~> 0.2` runtime dependency (replaces `typed_bus`).

## [0.1.0] - 2026-05-07

- Initial release
