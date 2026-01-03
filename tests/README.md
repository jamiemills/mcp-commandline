# Test Suite for MCP Command-line Tool

This directory contains comprehensive tests for the MCP command-line tool, covering CLI selection, validation, and edge cases.

## Test Files

### `test_cli_selection.sh`
Tests for the CLI selection feature (--cli option and preference persistence).

**Coverage:**
- Claude Code command generation
- Sourcegraph Amp command generation
- Config file creation and persistence
- Saved preference usage and override
- Default behavior
- Transport types (HTTP, SSE, stdio)
- Environment variables and headers
- Type inference
- Scope options
- Help documentation

**Tests:** 20

### `test_validation.sh`
Tests for input validation and edge cases.

**Coverage:**
- JSON validation
- Server name validation (alphanumeric, hyphens, underscores)
- URL validation (protocol, format, IPv4, IPv6, localhost)
- Transport-specific field requirements
- Environment variable name validation (POSIX shell names)
- Scope validation
- Type inference ambiguity detection
- Array and object type validation

**Tests:** 25

### `run_all_tests.sh`
Master test runner that executes all test suites and provides a summary.

## Running Tests

### Run all tests
```bash
./tests/run_all_tests.sh
```

### Run specific test suite
```bash
./tests/test_cli_selection.sh
./tests/test_validation.sh
```

### Run individual test (from within test script)
Edit the test script and comment out tests you don't want to run, or modify the `main()` function.

## Test Results

All tests use isolated test directories to avoid interfering with your system configuration.

### Color-coded Output
- 🟢 **Green** - Test passed
- 🔴 **Red** - Test failed
- 🟡 **Yellow** - Warnings or informational messages

## Test Statistics

- **Total tests:** 45
- **Test suites:** 2
- **Areas covered:** CLI selection, validation, configuration persistence, error handling

## Test Isolation

Each test:
1. Sets up a temporary config directory
2. Runs in isolation (no interaction with system config)
3. Cleans up after itself

This ensures tests don't interfere with each other or your actual configuration.

## Adding New Tests

To add a new test:

1. Create a new test function following the naming convention `test_<description>`
2. Add it to the appropriate test suite file
3. Call `run_test "Test description" test_function_name` in the `main()` function
4. Update `TESTS_RUN` counter if needed

Example:
```bash
test_my_new_feature() {
    local output
    output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com"}')
    [[ "$output" == "expected output" ]]
}

# In main():
run_test "My new feature" test_my_new_feature
```

## Continuous Integration

These tests are designed to work with CI/CD pipelines. Exit code 0 indicates all tests passed.

```bash
./tests/run_all_tests.sh && echo "Tests passed" || echo "Tests failed"
```

## Test Requirements

- Bash 4.0+
- `jq` (JSON query utility)
- Write access to temporary directories (for test config isolation)

## Known Limitations

1. **Query string URLs:** The URL validation doesn't currently support query strings (e.g., `?key=value`). Fragments are supported.
2. **IPv6 addresses:** IPv6 addresses in URLs are supported but must be in bracket notation (e.g., `https://[2001:db8::1]:8080`)

## Contributing

When adding new features to the main script:
1. Add corresponding tests to this suite
2. Ensure all existing tests still pass
3. Run the full test suite before committing
