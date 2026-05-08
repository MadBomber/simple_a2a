# Storage API

## Storage::Base

Abstract interface. Subclass this to implement custom storage backends.

```ruby
class MyStorage < A2A::Storage::Base
  def save(task)  = …   # persist, return task
  def find(id)    = …   # return task or nil
  def find!(id)   = …   # return task or raise A2A::TaskNotFoundError
  def delete(id)  = …   # remove task
  def list        = …   # return array of all tasks
end
```

Pass your custom storage to `Server::Base`:

```ruby
A2A::Server::Base.new(
  agent_card: card,
  executor:   MyExecutor.new,
  storage:    MyStorage.new
)
```

---

## Storage::Memory

Thread-safe in-process hash store backed by a `Mutex`. Sufficient for single-process servers. Data is lost on restart.

```ruby
storage = A2A::Storage::Memory.new

storage.save(task)          # => task
storage.find("task-id")     # => task or nil
storage.find!("task-id")    # => task or raises A2A::TaskNotFoundError
storage.delete("task-id")   # => removed task or nil
storage.list                # => [task, …]
storage.size                # => Integer
storage.clear               # clears all tasks
```

All methods acquire a mutex lock — safe for concurrent Falcon fibers.

---

## Custom storage example (Redis sketch)

```ruby
require "redis"

class RedisStorage < A2A::Storage::Base
  def initialize(redis: Redis.new)
    @redis = redis
  end

  def save(task)
    @redis.set("a2a:task:#{task.id}", task.to_h.to_json)
    task
  end

  def find(id)
    raw = @redis.get("a2a:task:#{id}")
    return nil unless raw
    A2A::Models::Task.from_hash(JSON.parse(raw))
  end

  def find!(id)
    find(id) or raise A2A::TaskNotFoundError, "Task #{id} not found"
  end

  def delete(id)
    @redis.del("a2a:task:#{id}")
  end

  def list
    keys = @redis.keys("a2a:task:*")
    return [] if keys.empty?
    @redis.mget(*keys).compact.map { |raw| A2A::Models::Task.from_hash(JSON.parse(raw)) }
  end
end
```
