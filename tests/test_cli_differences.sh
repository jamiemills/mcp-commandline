#!/bin/bash

# Test suite for CLI-specific differences (Spec 03, 04, 05)
# Tests header formatting, scope handling, and includeTools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/json-to-mcp-add.sh"
TEST_CONFIG_DIR="${XDG_CONFIG_HOME:=$HOME/.config}/mcp-commandline-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup function
cleanup() {
	rm -rf "$TEST_CONFIG_DIR" 2>/dev/null || true
}

# Setup function
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

# ==============================================================================
# Header Format Tests (Spec 03)
# ==============================================================================

# Test: Claude Code header uses colon-space format
test_claude_header_format_colon() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","headers":{"Auth":"token"}}')
	[[ "$output" == *'--header "Auth: token"'* ]]
}

# Test: Amp header uses equals format
test_amp_header_format_equals() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com","headers":{"Auth":"token"}}')
	[[ "$output" == *'--header "Auth=token"'* ]]
}

# Test: Claude with multiple headers
test_claude_multiple_headers() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","headers":{"A":"1","B":"2"}}')
	[[ "$output" == *'--header "A: 1"'* ]] && [[ "$output" == *'--header "B: 2"'* ]]
}

# Test: Amp with multiple headers
test_amp_multiple_headers() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com","headers":{"A":"1","B":"2"}}')
	[[ "$output" == *'--header "A=1"'* ]] && [[ "$output" == *'--header "B=2"'* ]]
}

# Test: Header value with spaces preserved
test_header_value_with_spaces() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","headers":{"Auth":"Bearer token123"}}')
	[[ "$output" == *'--header "Auth: Bearer token123"'* ]]
}

# Test: Header value with equals sign (value preserved)
test_header_value_with_equals() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com","headers":{"Auth":"token=abc=def"}}')
	[[ "$output" == *'--header "Auth=token=abc=def"'* ]]
}

# ==============================================================================
# Scope Handling Tests (Spec 04)
# ==============================================================================

# Test: Claude accepts scope=local
test_claude_scope_local() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","scope":"local"}')
	[[ "$output" == *"--scope local"* ]]
}

# Test: Claude accepts scope=project
test_claude_scope_project() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","scope":"project"}')
	[[ "$output" == *"--scope project"* ]]
}

# Test: Claude accepts scope=user
test_claude_scope_user() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","scope":"user"}')
	[[ "$output" == *"--scope user"* ]]
}

# Test: Amp rejects scope with error
test_amp_rejects_scope() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com","scope":"project"}' 2>&1) && return 1
	[[ "$output" == *"scope"* ]] && [[ "$output" == *"not supported"* ]]
}

# Test: Claude without scope produces no scope flag
test_claude_no_scope_no_flag() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" != *"--scope"* ]]
}

# Test: Amp without scope works fine
test_amp_no_scope_works() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" == "amp mcp add test https://api.example.com" ]]
}

# Test: Claude scope for stdio comes before --
test_claude_stdio_scope_before_separator() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"python","args":["server.py"],"scope":"project"}')
	# Scope should appear before --
	[[ "$output" == *"--scope project --"* ]]
}

# ==============================================================================
# Transport Flag Tests (Spec 02)
# ==============================================================================

# Test: Claude includes transport flag for HTTP
test_claude_transport_flag_http() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" == *"--transport http"* ]]
}

# Test: Claude includes transport flag for SSE
test_claude_transport_flag_sse() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","type":"sse","url":"https://api.example.com/sse"}')
	[[ "$output" == *"--transport sse"* ]]
}

# Test: Claude includes transport flag for stdio
test_claude_transport_flag_stdio() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"python"}')
	[[ "$output" == *"--transport stdio"* ]]
}

# Test: Amp omits transport flag for HTTP
test_amp_omits_transport_flag_http() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com"}')
	[[ "$output" != *"--transport"* ]]
}

# Test: Amp omits transport flag for stdio
test_amp_omits_transport_flag_stdio() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","command":"python"}')
	[[ "$output" != *"--transport"* ]]
}

# ==============================================================================
# includeTools Tests (Spec 05) - Amp Only
# ==============================================================================

# Test: includeTools valid for Amp stdio (no error)
test_amp_includetools_stdio_valid() {
	# includeTools is not included in CLI output, but should not cause error
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","command":"python","includeTools":["get_*","list_*"]}' 2>&1)
	if XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","command":"python","includeTools":["get_*","list_*"]}' >/dev/null 2>&1; then
		[[ "$output" == "amp mcp add test stdio python" ]]
	else
		return 1
	fi
}

# Test: includeTools rejected for HTTP transport
test_amp_includetools_http_rejected() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","url":"https://api.example.com","includeTools":["get_*"]}' 2>&1) && return 1
	[[ "$output" == *"includeTools"* ]] && [[ "$output" == *"stdio"* ]]
}

# Test: includeTools invalid pattern (brace expansion) rejected
test_amp_includetools_invalid_brace() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","command":"python","includeTools":["get_{a,b}"]}' 2>&1) && return 1
	[[ "$output" == *"brace expansion"* ]]
}

# Test: includeTools invalid pattern (recursive) rejected
test_amp_includetools_invalid_recursive() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","command":"python","includeTools":["**/private"]}' 2>&1) && return 1
	[[ "$output" == *"recursive"* ]]
}

# ==============================================================================
# Separator Tests (Claude vs Amp)
# ==============================================================================

# Test: Claude stdio includes -- separator
test_claude_stdio_has_separator() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"python","args":["server.py"]}')
	[[ "$output" == *" -- "* ]]
}

# Test: Amp stdio omits -- separator
test_amp_stdio_no_separator() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli amp '{"name":"test","command":"python","args":["server.py"]}')
	[[ "$output" != *" -- "* ]]
}

# ==============================================================================
# Run all tests
# ==============================================================================

main() {
	echo "=========================================="
	echo "MCP CLI Differences Test Suite"
	echo "=========================================="
	echo ""

	# Header format tests
	run_test "Claude header format (colon)" test_claude_header_format_colon
	run_test "Amp header format (equals)" test_amp_header_format_equals
	run_test "Claude multiple headers" test_claude_multiple_headers
	run_test "Amp multiple headers" test_amp_multiple_headers
	run_test "Header value with spaces" test_header_value_with_spaces
	run_test "Header value with equals sign" test_header_value_with_equals

	# Scope tests
	run_test "Claude accepts scope=local" test_claude_scope_local
	run_test "Claude accepts scope=project" test_claude_scope_project
	run_test "Claude accepts scope=user" test_claude_scope_user
	run_test "Amp rejects scope with error" test_amp_rejects_scope
	run_test "Claude no scope = no flag" test_claude_no_scope_no_flag
	run_test "Amp no scope works" test_amp_no_scope_works
	run_test "Claude stdio scope before --" test_claude_stdio_scope_before_separator

	# Transport flag tests
	run_test "Claude transport flag for HTTP" test_claude_transport_flag_http
	run_test "Claude transport flag for SSE" test_claude_transport_flag_sse
	run_test "Claude transport flag for stdio" test_claude_transport_flag_stdio
	run_test "Amp omits transport flag (HTTP)" test_amp_omits_transport_flag_http
	run_test "Amp omits transport flag (stdio)" test_amp_omits_transport_flag_stdio

	# includeTools tests
	run_test "Amp includeTools valid for stdio" test_amp_includetools_stdio_valid
	run_test "Amp includeTools rejected for HTTP" test_amp_includetools_http_rejected
	run_test "Amp includeTools invalid (brace)" test_amp_includetools_invalid_brace
	run_test "Amp includeTools invalid (recursive)" test_amp_includetools_invalid_recursive

	# Separator tests
	run_test "Claude stdio has -- separator" test_claude_stdio_has_separator
	run_test "Amp stdio no -- separator" test_amp_stdio_no_separator

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
