#!/bin/bash

# Test suite for CLI selection feature
# Tests the --cli option and preference persistence

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/json-to-mcp-add.sh"
TEST_CONFIG_DIR="${XDG_CONFIG_HOME:=$HOME/.config}/mcp-commandline-test"
TEST_FALLBACK_CONFIG="$HOME/.mcp-commandline-config-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup function
cleanup() {
	rm -rf "$TEST_CONFIG_DIR" 2>/dev/null || true
	rm -f "$TEST_FALLBACK_CONFIG" 2>/dev/null || true
}

# Setup function - run before each test
setup() {
	cleanup
	mkdir -p "$TEST_CONFIG_DIR"
}

# Helper function to run a test
run_test() {
	local test_name="$1"
	local test_func="$2"

	TESTS_RUN=$((TESTS_RUN + 1))

	echo -n "Running: $test_name ... "

	if setup && $test_func; then
		echo -e "${GREEN}✓ PASSED${NC}"
		TESTS_PASSED=$((TESTS_PASSED + 1))
	else
		echo -e "${RED}✗ FAILED${NC}"
		TESTS_FAILED=$((TESTS_FAILED + 1))
	fi
}

# Helper to run script with test config
run_with_test_config() {
	XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" "$@"
}

# Test 1: Claude Code output generation
test_claude_output() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" == "claude mcp add --transport http test https://api.example.com" ]]
}

# Test 2: Sourcegraph Amp output generation
test_amp_output() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" == "amp mcp add test https://api.example.com" ]]
}

# Test 3: Config file is created with --cli claude
test_config_creation_claude() {
	XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com"}' >/dev/null
	[[ -f "$TEST_CONFIG_DIR/mcp-commandline/config" ]]
}

# Test 4: Config file is created with --cli amp
test_config_creation_amp() {
	XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com"}' >/dev/null
	[[ -f "$TEST_CONFIG_DIR/mcp-commandline/config" ]]
}

# Test 5: Saved preference is used
test_saved_preference() {
	# Set preference to amp
	XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com"}' >/dev/null

	# Run without --cli and verify it uses amp
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" '{"name":"test2","url":"https://api.example.com"}')
	[[ "$output" == "amp mcp add test2 https://api.example.com" ]]
}

# Test 6: Override saved preference
test_override_preference() {
	# Set preference to amp
	XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com"}' >/dev/null

	# Override with claude
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test2","url":"https://api.example.com"}')
	[[ "$output" == "claude mcp add --transport http test2 https://api.example.com" ]]

	# Verify new preference was saved
	local saved_config
	saved_config=$(cat "$TEST_CONFIG_DIR/mcp-commandline/config")
	[[ "$saved_config" == "CLI_TYPE=claude" ]]
}

# Test 7: Default to claude if no config exists
test_default_to_claude() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" == "claude mcp add --transport http test https://api.example.com" ]]
}

# Test 8: Invalid CLI type rejected
test_invalid_cli_type() {
	XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli invalid '{"name":"test","url":"https://api.example.com"}' >/dev/null 2>&1 && return 1
	return 0
}

# Test 9: Claude with stdio and env vars
# Note: Per Spec 07, env vars are appended after command and args
test_claude_stdio() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"postgres","command":"npx","args":["@mcp/server"],"env":{"PGUSER":"admin"}}')
	[[ "$output" == "claude mcp add --transport stdio postgres -- npx @mcp/server PGUSER=\"admin\"" ]]
}

# Test 10: Amp with HTTP and headers
# Note: Amp uses equals format (Key=Value) per Spec 03
test_amp_headers() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"api","url":"https://api.example.com","headers":{"Authorization":"Bearer token"}}')
	[[ "$output" == "amp mcp add api https://api.example.com --header \"Authorization=Bearer token\"" ]]
}

# Test 11: Multiple headers
test_multiple_headers() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"api","url":"https://api.example.com","headers":{"Authorization":"Bearer token","X-Custom":"value"}}')
	# Check that both headers are present (order may vary)
	[[ "$output" == *"--header \"Authorization: Bearer token\""* ]] && [[ "$output" == *"--header \"X-Custom: value\""* ]]
}

# Test 12: CLI option without value is rejected
test_cli_missing_value() {
	# The script should exit with error code 1 when --cli has no value
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli >/dev/null 2>&1
}

# Test 13: Type inference (url only = http)
test_type_inference_http() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" == "claude mcp add --transport http test https://api.example.com" ]]
}

# Test 14: Type inference (command only = stdio)
test_type_inference_stdio() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"npx","args":["@mcp/server"]}')
	[[ "$output" == "claude mcp add --transport stdio test -- npx @mcp/server" ]]
}

# Test 15: Config stored in correct format
test_config_format() {
	XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com"}' >/dev/null
	local config
	config=$(cat "$TEST_CONFIG_DIR/mcp-commandline/config")
	[[ "$config" == "CLI_TYPE=amp" ]]
}

# Test 16: Claude Desktop config format (multiple servers)
test_claude_desktop_format() {
	local output
	output=$(
		XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp <<'EOF'
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://mcp.github.com"
    }
  }
}
EOF
	)
	[[ "$output" == "amp mcp add github https://mcp.github.com" ]]
}

# Test 17: SSE transport type
test_sse_transport() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","type":"sse","url":"https://api.example.com/sse"}')
	[[ "$output" == "claude mcp add --transport sse test https://api.example.com/sse" ]]
}

# Test 18: Scope option for http
test_scope_http() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","scope":"project"}')
	[[ "$output" == "claude mcp add --transport http test https://api.example.com --scope project" ]]
}

# Test 19: Scope option for stdio (must come before --)
test_scope_stdio() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"npx","args":["@mcp/server"],"scope":"project"}')
	[[ "$output" == "claude mcp add --transport stdio test --scope project -- npx @mcp/server" ]]
}

# Test 20: Help output contains CLI selection docs
test_help_contains_cli_docs() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --help 2>&1)
	[[ "$output" == *"--cli"* ]] && [[ "$output" == *"claude"* ]] && [[ "$output" == *"amp"* ]]
}

# Run all tests
main() {
	echo "=========================================="
	echo "MCP Command-line CLI Selection Test Suite"
	echo "=========================================="
	echo ""

	run_test "Claude Code output generation" test_claude_output
	run_test "Sourcegraph Amp output generation" test_amp_output
	run_test "Config file creation (claude)" test_config_creation_claude
	run_test "Config file creation (amp)" test_config_creation_amp
	run_test "Use saved preference" test_saved_preference
	run_test "Override saved preference" test_override_preference
	run_test "Default to claude if no config" test_default_to_claude
	run_test "Reject invalid CLI type" test_invalid_cli_type
	run_test "Claude with stdio and env vars" test_claude_stdio
	run_test "Amp with HTTP and headers" test_amp_headers
	run_test "Multiple headers" test_multiple_headers
	run_test "CLI missing value rejected" test_cli_missing_value
	run_test "Type inference (http)" test_type_inference_http
	run_test "Type inference (stdio)" test_type_inference_stdio
	run_test "Config file format" test_config_format
	run_test "Claude Desktop format" test_claude_desktop_format
	run_test "SSE transport type" test_sse_transport
	run_test "Scope option (http)" test_scope_http
	run_test "Scope option (stdio)" test_scope_stdio
	run_test "Help contains CLI docs" test_help_contains_cli_docs

	echo ""
	echo "=========================================="
	echo "Test Results"
	echo "=========================================="
	echo "Tests run:    $TESTS_RUN"
	echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
	if [ $TESTS_FAILED -gt 0 ]; then
		echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
	else
		echo -e "Tests failed: ${GREEN}0${NC}"
	fi
	echo ""

	cleanup

	if [ $TESTS_FAILED -gt 0 ]; then
		exit 1
	fi
}

main "$@"
