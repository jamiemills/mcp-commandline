#!/bin/bash

# Validation and edge case tests for the MCP command-line tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/json-to-mcp-add.sh"
TEST_CONFIG_DIR="${XDG_CONFIG_HOME:=$HOME/.config}/mcp-commandline-test-val"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

cleanup() {
	rm -rf "$TEST_CONFIG_DIR" 2>/dev/null || true
}

setup() {
	cleanup
	mkdir -p "$TEST_CONFIG_DIR"
}

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

# Test 1: Invalid JSON is rejected
test_invalid_json() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude 'invalid json' >/dev/null 2>&1
}

# Test 2: Missing name field is rejected
test_missing_name() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"url":"https://api.example.com"}' >/dev/null 2>&1
}

# Test 3: Invalid server name (with dots)
test_invalid_server_name_dots() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"server.name","url":"https://api.example.com"}' >/dev/null 2>&1
}

# Test 4: Invalid server name (with spaces)
test_invalid_server_name_spaces() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"server name","url":"https://api.example.com"}' >/dev/null 2>&1
}

# Test 5: Valid server name (with hyphens)
test_valid_server_name_hyphens() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"my-server","url":"https://api.example.com"}')
	[[ "$output" == "claude mcp add --transport http my-server https://api.example.com" ]]
}

# Test 6: Valid server name (with underscores)
test_valid_server_name_underscores() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"my_server","url":"https://api.example.com"}')
	[[ "$output" == "claude mcp add --transport http my_server https://api.example.com" ]]
}

# Test 7: Invalid URL (no protocol)
test_invalid_url_no_protocol() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"api.example.com"}' >/dev/null 2>&1
}

# Test 8: Invalid URL (wrong protocol)
test_invalid_url_wrong_protocol() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"ftp://api.example.com"}' >/dev/null 2>&1
}

# Test 9: Valid URL with port
test_valid_url_with_port() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com:3000"}')
	[[ "$output" == "claude mcp add --transport http test https://api.example.com:3000" ]]
}

# Test 10: Valid URL with path
test_valid_url_with_path() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com/mcp/v1"}')
	[[ "$output" == "claude mcp add --transport http test https://api.example.com/mcp/v1" ]]
}

# Test 11: URL with fragment (hash)
test_valid_url_with_fragment() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com/path#section"}')
	[[ "$output" == "claude mcp add --transport http test https://api.example.com/path#section" ]]
}

# Test 12: Valid URL with IPv4
test_valid_url_ipv4() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://192.168.1.1"}')
	[[ "$output" == "claude mcp add --transport http test https://192.168.1.1" ]]
}

# Test 13: Valid URL with localhost
test_valid_url_localhost() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"http://localhost:3000"}')
	[[ "$output" == "claude mcp add --transport http test http://localhost:3000" ]]
}

# Test 14: Missing URL for http transport
test_missing_url_http() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","type":"http"}' >/dev/null 2>&1
}

# Test 15: Missing command for stdio transport
test_missing_command_stdio() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","type":"stdio"}' >/dev/null 2>&1
}

# Test 16: Invalid env var name (starts with digit)
test_invalid_env_var_digit() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"npx","env":{"2INVALID":"value"}}' >/dev/null 2>&1
}

# Test 17: Valid env var name (starts with underscore)
# Note: Per Spec 07, env vars are appended as KEY="value" after args
test_valid_env_var_underscore() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"npx","env":{"_VAR":"value"}}')
	[[ "$output" == *"_VAR=\"value\""* ]]
}

# Test 18: Invalid scope value
test_invalid_scope() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","scope":"invalid"}' >/dev/null 2>&1
}

# Test 19: Valid scope (project)
test_valid_scope_project() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","scope":"project"}')
	[[ "$output" == *"--scope project"* ]]
}

# Test 20: Valid scope (user)
test_valid_scope_user() {
	local output
	output=$(XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","scope":"user"}')
	[[ "$output" == *"--scope user"* ]]
}

# Test 21: Ambiguous type (both command and url)
test_ambiguous_type() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"npx","url":"https://api.example.com"}' >/dev/null 2>&1
}

# Test 22: No transport type and can't infer
test_no_transport_type() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test"}' >/dev/null 2>&1
}

# Test 23: Args must be array
test_args_not_array() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"npx","args":"not-array"}' >/dev/null 2>&1
}

# Test 24: Headers must be object
test_headers_not_object() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","url":"https://api.example.com","headers":"not-object"}' >/dev/null 2>&1
}

# Test 25: Env must be object
test_env_not_object() {
	! XDG_CONFIG_HOME="$TEST_CONFIG_DIR" "$SCRIPT" --cli claude '{"name":"test","command":"npx","env":"not-object"}' >/dev/null 2>&1
}

main() {
	echo "=========================================="
	echo "MCP Validation and Edge Cases Test Suite"
	echo "=========================================="
	echo ""

	run_test "Invalid JSON is rejected" test_invalid_json
	run_test "Missing name field is rejected" test_missing_name
	run_test "Invalid server name (dots)" test_invalid_server_name_dots
	run_test "Invalid server name (spaces)" test_invalid_server_name_spaces
	run_test "Valid server name (hyphens)" test_valid_server_name_hyphens
	run_test "Valid server name (underscores)" test_valid_server_name_underscores
	run_test "Invalid URL (no protocol)" test_invalid_url_no_protocol
	run_test "Invalid URL (wrong protocol)" test_invalid_url_wrong_protocol
	run_test "Valid URL with port" test_valid_url_with_port
	run_test "Valid URL with path" test_valid_url_with_path
	run_test "URL with fragment (hash)" test_valid_url_with_fragment
	run_test "Valid URL with IPv4" test_valid_url_ipv4
	run_test "Valid URL with localhost" test_valid_url_localhost
	run_test "Missing URL for http transport" test_missing_url_http
	run_test "Missing command for stdio transport" test_missing_command_stdio
	run_test "Invalid env var name (digit)" test_invalid_env_var_digit
	run_test "Valid env var name (underscore)" test_valid_env_var_underscore
	run_test "Invalid scope value" test_invalid_scope
	run_test "Valid scope (project)" test_valid_scope_project
	run_test "Valid scope (user)" test_valid_scope_user
	run_test "Ambiguous type (both fields)" test_ambiguous_type
	run_test "No transport type inferrable" test_no_transport_type
	run_test "Args must be array" test_args_not_array
	run_test "Headers must be object" test_headers_not_object
	run_test "Env must be object" test_env_not_object

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
