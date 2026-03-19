# Testing LiteFillR

## Running Tests

To run the full test suite:

```bash
cd LiteFillR
bundle exec ruby test/run_tests.rb
```

To run a specific test file:

```bash
bundle exec ruby -Itest test/test_kv_store.rb
```

## Test Structure

The test suite uses Minitest and is organized into the following files:

| File | Description | Test Count |
|------|-------------|------------|
| `test_constants.rb` | Tests for file mode constants (S_IFREG, S_IFDIR, etc.) | 4 |
| `test_errors.rb` | Tests for ErrnoException and error codes | 5 |
| `test_guards.rb` | Tests for validation guard functions | 18 |
| `test_kv_store.rb` | Tests for key-value store operations | 19 |
| `test_tool_calls.rb` | Tests for tool call tracking | 22 |
| `test_filesystem.rb` | Tests for filesystem operations | 47 |
| `test_agentfs.rb` | Integration tests for main AgentFS class | 17 |

**Total: 168 tests, 600+ assertions**

## Test Categories

### Unit Tests

- **Constants**: Verify file type masks, default permissions, chunk size
- **Errors**: Verify ErrnoException stores correct code, syscall, path, message
- **Guards**: Test directory/file/symlink mode detection, validation functions

### Component Tests

- **KvStore**: set/get/delete, list by prefix, keys, clear, complex data, unicode, timestamps
- **ToolCalls**: start/success/error/record, get by name/recent, statistics
- **Filesystem**: write/read, mkdir/rmdir/readdir, stat, unlink/rm, rename, copy, existence checks

### Integration Tests

- Full workflow combining KV, FS, and tool calls
- Persistence across database reopens
- Error handling for all POSIX error codes
- Complex nested directory operations
- Large data handling (1MB files, 10K item arrays)
- Unicode support throughout
- Stress testing (100 files, 100 KV entries)

## Writing New Tests

Tests inherit from `LiteFillRTest` which provides:

- `test_db_path(name)` - Get path to test database
- `with_database(name) { |db| ... }` - Create temp database
- `with_agentfs(name) { |agent| ... }` - Create temp AgentFS instance
- Automatic cleanup of test databases

Example:

```ruby
class TestMyFeature < LiteFillRTest
  def test_something
    with_agentfs do |agent|
      agent.kv.set("key", "value")
      assert_equal "value", agent.kv.get("key")
    end
  end
end
```
