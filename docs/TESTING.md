# Testing Guide - MCP Command-line Tool

## Quick Start

```bash
# Run all tests
./tests/run_all_tests.sh

# Run specific test suite
./tests/test_cli_selection.sh
./tests/test_validation.sh
```

## Test Files Location

All test files are saved in: `/Users/jamiemills/Projects/code/mcp-commandline/tests/`

### Files

- **`test_cli_selection.sh`** - 20 tests for CLI selection feature
  - Tests the `--cli` option
  - Tests preference persistence
  - Tests Claude Code and Amp command generation

- **`test_validation.sh`** - 25 tests for validation and edge cases
  - Tests JSON validation
  - Tests input validation rules
  - Tests error handling
  - Tests boundary conditions

- **`run_all_tests.sh`** - Master test runner
  - Runs all test suites
  - Provides summary report
  - Returns exit code 0 (success) or 1 (failure)

- **`README.md`** - Test documentation
  - Detailed test descriptions
  - Coverage information
  - Instructions for adding new tests

## Reports

- **`docs/TEST_REPORT.md`** - Comprehensive test report
  - Full test results
  - Feature testing summary
  - Code quality analysis
  - Known limitations

## How Tests Work

### Test Isolation
Each test runs in isolation using a temporary config directory. Tests do not interfere with:
- Your system configuration
- Each other
- The main application

### Config Directory Setup
Tests use `$XDG_CONFIG_HOME` environment variable set to a temporary directory:
```bash
XDG_CONFIG_HOME="/tmp/mcp-commandline-test" ./json-to-mcp-add.sh ...
```

### Cleanup
Temporary config directories are automatically cleaned up after each test.

## Running Tests

### All Tests
```bash
./tests/run_all_tests.sh
```

Output:
```
╔════════════════════════════════════════════════════════════╗
║         MCP Command-line Tool - Complete Test Suite        ║
╚════════════════════════════════════════════════════════════╝

Running: CLI Selection Tests
─────────────────────────────────────────────────────────────
✓ CLI Selection tests passed

Running: Validation and Edge Cases Tests
─────────────────────────────────────────────────────────────
✓ Validation tests passed

╔════════════════════════════════════════════════════════════╗
║                      SUMMARY                               ║
╚════════════════════════════════════════════════════════════╝

Test suites run:    2
Test suites passed: 2
Test suites failed: 0

All tests passed!
```

### Individual Suite
```bash
./tests/test_cli_selection.sh
```

```bash
./tests/test_validation.sh
```

### In CI/CD
```bash
if ./tests/run_all_tests.sh; then
    echo "All tests passed"
    exit 0
else
    echo "Some tests failed"
    exit 1
fi
```

## Test Statistics

| Metric | Value |
|--------|-------|
| Total Tests | 45 |
| CLI Selection Tests | 20 |
| Validation Tests | 25 |
| Pass Rate | 100% |
| Code Quality | 0 warnings |

## Test Categories

### Feature Tests (20 tests)
- CLI selection: Claude Code and Amp
- Preference persistence and override
- Default behavior
- Transport types
- Headers and environment variables
- Type inference
- Scope options

### Validation Tests (25 tests)
- JSON validation
- Server name validation
- URL validation (protocol, format, special cases)
- Transport-specific requirements
- Environment variable names
- Scope values
- Type ambiguity detection
- Object and array type validation

## Test Examples

### Test CLI Selection Works
```bash
# Run manually
./json-to-mcp-add.sh --cli claude '{"name":"test","url":"https://api.example.com"}'

# Expected output
claude mcp add --transport http test https://api.example.com
```

### Test Preference Persistence
```bash
# Set preference to Amp
./json-to-mcp-add.sh --cli amp '{"name":"test","url":"https://api.example.com"}'

# Use saved preference (should output amp command)
./json-to-mcp-add.sh '{"name":"test","url":"https://api.example.com"}'
```

### Test Validation
```bash
# Invalid CLI type (should fail)
./json-to-mcp-add.sh --cli invalid '{"name":"test","url":"https://api.example.com"}' 2>&1
# Error: Invalid CLI type 'invalid'. Must be: claude, amp

# Invalid URL (should fail)
./json-to-mcp-add.sh --cli claude '{"name":"test","url":"not-a-url"}' 2>&1
# Error: Invalid URL format for 'not-a-url'. Must be valid HTTP(S) URL
```

## Adding New Tests

To add a new test to the suite:

1. **Create test function** in appropriate file (`test_cli_selection.sh` or `test_validation.sh`)
2. **Follow naming convention**: `test_<description>`
3. **Implement test logic**: Use assertions to verify expected behavior
4. **Add to main()**: Call `run_test "Description" test_function_name`

Example:
```bash
# In test_cli_selection.sh

test_my_feature() {
    local output
    output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com"}')
    [[ "$output" == "expected output" ]]
}

# In main():
run_test "My feature works" test_my_feature
```

## Debugging Tests

### Run a single test manually
```bash
# Set up test environment
TEST_CONFIG_DIR="/tmp/test-debug"
mkdir -p "$TEST_CONFIG_DIR"

# Run command with test config
XDG_CONFIG_HOME="$TEST_CONFIG_DIR" ./json-to-mcp-add.sh --cli claude '{"name":"test","url":"https://api.example.com"}'

# Check config was created
cat "$TEST_CONFIG_DIR/mcp-commandline/config"
```

### Enable verbose output
Edit test script and add `set -x` at the top:
```bash
set -euxo pipefail
```

This will print each command as it executes.

## Troubleshooting

### Test fails with "command not found"
Ensure you're running tests from the project root:
```bash
cd /Users/jamiemills/Projects/code/mcp-commandline
./tests/run_all_tests.sh
```

### Permission denied
Make sure test scripts are executable:
```bash
chmod +x tests/*.sh
```

### Config files not cleaning up
Tests should clean up automatically, but if needed:
```bash
rm -rf ~/.config/mcp-commandline-test*
rm -f ~/.mcp-commandline-config-test*
```

## Code Quality Checks

Tests include validation for:
- **Shellcheck** - Static shell script analysis
- **Shfmt** - Shell script formatting

Run manually:
```bash
shellcheck json-to-mcp-add.sh
shfmt -d json-to-mcp-add.sh
```

## See Also

- `README.md` - Main project documentation
- `docs/TEST_REPORT.md` - Detailed test report
- `tests/README.md` - Test suite documentation
