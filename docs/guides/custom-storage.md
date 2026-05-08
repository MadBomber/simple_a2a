# Custom Storage

The default `Storage::Memory` is ephemeral — tasks are lost on restart. For production, implement `Storage::Base`.

## Interface

```ruby
class A2A::Storage::Base
  def save(task)  = raise NotImplementedError
  def find(id)    = raise NotImplementedError   # nil if missing
  def find!(id)   = raise NotImplementedError   # raises TaskNotFoundError if missing
  def delete(id)  = raise NotImplementedError
  def list        = raise NotImplementedError   # returns Array
end
```

## Minimal example

```ruby
class HashStorage < A2A::Storage::Base
  def initialize
    @store = {}
  end

  def save(task)
    @store[task.id] = task
  end

  def find(id)
    @store[id]
  end

  def find!(id)
    @store.fetch(id) { raise A2A::TaskNotFoundError, "Task #{id} not found" }
  end

  def delete(id)
    @store.delete(id)
  end

  def list
    @store.values
  end
end
```

## Serialization

`A2A::Models::Task` supports round-trip serialization via `to_h` and `from_hash`:

```ruby
hash = task.to_h                         # => { "id" => "…", "status" => {…}, … }
task = A2A::Models::Task.from_hash(hash) # => reconstructed Task
```

Use this for any storage backend that persists JSON (databases, Redis, files):

```ruby
def save(task)
  db.set(task.id, task.to_h.to_json)
  task
end

def find(id)
  raw = db.get(id)
  return nil unless raw
  A2A::Models::Task.from_hash(JSON.parse(raw))
end
```
