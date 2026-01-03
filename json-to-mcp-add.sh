#!/bin/bash

set -euo pipefail

# Usage information
usage() {
	cat <<EOF
Usage: $0 [OPTIONS] [JSON_INPUT]

Convert JSON MCP server configuration to CLI-specific MCP add commands.

Input can be provided as:
  - First argument: $0 '{"name":"server","url":"https://..."}'
  - stdin: echo '{"name":"server",...}' | $0

Options:
  -c, --cli TYPE   Specify CLI platform: 'claude' (default) or 'amp'
                   Preference is saved to $HOME/.config/mcp-commandline/config for future use
  -x, --execute    Execute the command instead of printing it
  -h, --help       Show this help message

Examples:

  Generate Claude Code command:
    $0 --cli claude '{"name":"notion","url":"https://mcp.notion.com"}'
    Output: claude mcp add --transport http notion https://mcp.notion.com

  Generate Sourcegraph Amp command:
    $0 --cli amp '{"name":"github","url":"https://mcp.github.com"}'
    Output: amp mcp add github https://mcp.github.com

  Execute the command directly:
    $0 --cli claude --execute < config.json

  Use saved preference (no --cli option required after first use):
    $0 '{"name":"server","url":"https://..."}'
    Uses the CLI type from previous invocation

Transport Type Inference:

The 'type' field is optional and will be automatically inferred from the
configuration structure if not provided:
  - If 'command' is present and 'url' is absent → stdio transport
  - If 'url' is present and 'command' is absent → http transport

If both 'command' and 'url' are present, or neither is present, the 'type'
field must be explicitly provided.

Supported JSON Formats:

Format 1 (Flat):
  {
    "name": "server-name",           (required)
    "type": "http|sse|stdio",        (optional, can be inferred)
    "url": "https://...",            (required for http/sse)
    "command": "/path/to/cmd",       (required for stdio)
    "args": ["arg1", "arg2"],        (optional for stdio)
    "headers": {                     (optional for http/sse)
      "Key": "Value"
    },
    "env": {                         (optional for stdio)
      "VAR": "value"
    },
    "scope": "local|project|user"    (optional)
  }

Format 2 (Claude Desktop config):
  {
    "mcpServers": {
      "server-name": {
        "type": "http|sse|stdio",    (optional, can be inferred)
        "url": "https://...",        (required for http/sse)
        "command": "/path/to/cmd",   (required for stdio)
        "args": [...],               (optional for stdio)
        "headers": {...},            (optional for http/sse)
        "env": {...}                 (optional for stdio)
      }
    }
  }
EOF
	exit 1
}

# ==============================================================================
# Validation Framework (Spec 01)
# ==============================================================================
#
# These functions validate MCP server configurations against the official MCP schema.
# Schema source: https://modelcontextprotocol.io/specification/2025-11-25
# Claude Code docs: https://code.claude.com/docs/en/mcp
# Amp docs: https://ampcode.com/manual#mcp
#

# List of known valid fields for unknown field detection
KNOWN_FIELDS=("name" "url" "command" "type" "headers" "args" "env" "scope" "includeTools")

# Validate URL format (must be valid HTTP/HTTPS URL per RFC 3986)
#
# MCP Schema Rule: HTTP and SSE transports require a valid HTTPS or HTTP URL
# This validation enforces RFC 3986 generic URI syntax with these rules:
#   - Scheme: http:// or https:// (required)
#   - Host: domain name (RFC 1035), IPv4, IPv6 (RFC 3986), or localhost
#   - Port: optional decimal digits (1-5 characters), valid range 1-65535
#   - Path/Query/Fragment: optional after hostname
#   - Rejects: protocol-only URLs, wrong protocols, malformed addresses, spaces
#
# Host Format Support:
#   - Domain names: labels with alphanumeric and hyphens, hyphens not at start/end
#   - IPv4: dotted-decimal with octets 0-255
#   - IPv6: hexadecimal groups in brackets per RFC 3986
#   - Localhost: special case for local development
#
# Examples accepted:
#   https://api.example.com
#   https://api.example.com:3000
#   https://api.example.com/path?key=value#section
#   https://192.168.1.1
#   https://localhost:3000
#   https://[2001:db8::1]:8080
#
# Source: RFC 3986 - Uniform Resource Identifier (URI) Generic Syntax
# Source: MCP specification 2025-11-25 - HTTP/SSE transport requirements
validate_url() {
	local url="$1"

	# Empty URL is invalid
	if [ -z "$url" ]; then
		return 1
	fi

	# Check for spaces (not allowed in URLs)
	if [[ "$url" =~ [[:space:]] ]]; then
		return 1
	fi

	# RFC 3986 compliant URL regex supporting domains, IPv4, IPv6, and localhost
	# Pattern breakdown:
	#   https?://           - Protocol (http:// or https://)
	#   (host)              - Host can be one of:
	#                         - Domain: ([a-zA-Z0-9]..\.)*[a-zA-Z0-9]... (RFC 1035 labels)
	#                         - IPv6: \[...\] (hexadecimal groups in brackets)
	#                         - IPv4: dotted-decimal with octets 0-255
	#                         - localhost: special case
	#   (:[0-9]{1,5})?      - Optional port
	#   (/[^\s]*)?          - Optional path/query/fragment
	#   $                   - End of string
	local url_regex='^https?://(([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?|\[([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\]|localhost|127\.0\.0\.1|([0-9]{1,3}\.){3}[0-9]{1,3})(:[0-9]{1,5})?(/.*)?$'

	if [[ ! "$url" =~ $url_regex ]]; then
		return 1
	fi

	# Additional port validation - check if port is in valid range (1-65535)
	if [[ "$url" =~ :([0-9]+)(\/|$) ]]; then
		local port="${BASH_REMATCH[1]}"
		if [ "$port" -gt 65535 ] || [ "$port" -eq 0 ]; then
			return 1
		fi
	fi

	# Check for empty port (colon with no number)
	if [[ "$url" =~ :/[^/] ]] || [[ "$url" =~ :$ ]] || [[ "$url" =~ ://[^/]+:(/|$) ]]; then
		# This catches patterns like "http://example.com:" or "http://example.com:/"
		if [[ "$url" =~ ://[^/]+:(/|$) ]]; then
			return 1
		fi
	fi

	return 0
}

# Validate scope enum
#
# MCP Schema Rule: The scope field, when present, must be one of: local, project, user
#   - local: User-level configuration stored in ~/.claude.json (default)
#   - project: Repository-level configuration stored in .mcp.json (shared with team)
#   - user: Compatibility alias for local (same as local)
#
# Source: Claude Code configuration documentation - Scope options
validate_scope() {
	local scope="$1"
	if [[ ! "$scope" =~ ^(local|project|user)$ ]]; then
		return 1
	fi
	return 0
}

# Validate server name
#
# MCP Schema Rule: Server names must be valid identifiers for configuration storage
# Allowed characters:
#   - Alphanumeric (a-z, A-Z, 0-9)
#   - Hyphens (-)
#   - Underscores (_)
#
# Note: Must NOT contain special characters, spaces, or dots as these are used
# as configuration object keys and may conflict with object notation.
#
# Source: MCP specification - configuration object structure and naming conventions
validate_server_name() {
	local name="$1"
	local name_regex='^[a-zA-Z0-9_-]+$'

	if [[ ! "$name" =~ $name_regex ]]; then
		return 1
	fi
	return 0
}

# Validate environment variable name
#
# MCP Schema Rule: Environment variable names must follow POSIX shell variable naming convention
# Requirements:
#   - Must start with letter (a-z, A-Z) or underscore (_)
#   - Can contain letters, digits (0-9), and underscores
#   - Cannot start with a digit
#
# This ensures compatibility with shell execution and environment variable expansion.
#
# Source: POSIX shell specification and MCP environment variable handling
validate_env_var_name() {
	local var_name="$1"
	local var_regex='^[a-zA-Z_][a-zA-Z0-9_]*$'

	if [[ ! "$var_name" =~ $var_regex ]]; then
		return 1
	fi
	return 0
}

# Validate field is an object (JSON)
#
# MCP Schema Rule: Certain fields (headers, env) must be objects (key-value pairs)
# This validation ensures:
#   - Field is not null
#   - Field is valid JSON
#   - Field type is "object" (not string, array, number, boolean)
#
# Used for: headers (HTTP/SSE), env (stdio)
validate_is_object() {
	local field="$1"
	if [ "$field" = "null" ] || [ -z "$field" ]; then
		return 1
	fi
	if ! echo "$field" | jq empty 2>/dev/null; then
		return 1
	fi
	# Check if it's an object by looking for {}
	if ! echo "$field" | jq 'type == "object"' | grep -q "true"; then
		return 1
	fi
	return 0
}

# Validate field is an array (JSON)
#
# MCP Schema Rule: The args field must be an array of strings
# This validation ensures:
#   - Field is not null
#   - Field is valid JSON
#   - Field type is "array" (not string, object, number, boolean)
#
# Used for: args (stdio only)
validate_is_array() {
	local field="$1"
	if [ "$field" = "null" ] || [ -z "$field" ]; then
		return 1
	fi
	if ! echo "$field" | jq empty 2>/dev/null; then
		return 1
	fi
	# Check if it's an array
	if ! echo "$field" | jq 'type == "array"' | grep -q "true"; then
		return 1
	fi
	return 0
}

# Validate array contains only strings
#
# MCP Schema Rule: The args array must contain only string elements
# This ensures:
#   - Each array element is a string (not number, boolean, null, or object)
#   - Arguments can be properly passed to the command
#
# Note: Must validate actual JSON types, not just null values.
#
# Source: MCP stdio transport specification - args field definition
validate_array_of_strings() {
	local array="$1"

	# First validate it's an array
	if ! validate_is_array "$array"; then
		return 1
	fi

	# Check each element is a string type
	local non_string_count
	non_string_count=$(echo "$array" | jq '[.[] | type != "string"] | any' 2>/dev/null)
	if [ "$non_string_count" = "true" ]; then
		return 1
	fi

	return 0
}

# Validate transport type
#
# MCP Schema Rule: Transport type must be one of the supported values
# Supported types:
#   - http: Standard HTTP transport (recommended for remote servers)
#   - sse: Server-Sent Events (deprecated as of MCP 2025-03-26, use http)
#   - stdio: Local process via standard input/output
#
# Source: MCP specification - transport types
validate_transport_type() {
	local transport="$1"

	# Empty is invalid
	if [ -z "$transport" ]; then
		return 1
	fi

	# Must be one of the valid types
	if [[ ! "$transport" =~ ^(http|sse|stdio)$ ]]; then
		return 1
	fi

	return 0
}

# Validate header key
#
# HTTP header keys must follow RFC 7230 token rules:
#   - Cannot be empty
#   - Can contain: alphanumeric, hyphen, and certain special characters
#   - Cannot contain: space, tab, colon, comma, double quote
#
# Source: RFC 7230 - HTTP/1.1 Message Syntax and Routing
validate_header_key() {
	local key="$1"

	# Empty key is invalid
	if [ -z "$key" ]; then
		return 1
	fi

	# Cannot contain space, tab, colon, comma, double quote, or control characters
	if [[ "$key" =~ [[:space:]:|,\"] ]]; then
		return 1
	fi

	# Must match allowed characters: alphanumeric + allowed special chars
	# Allowed: ! # $ % & ' * + . ^ _ ` | ~ -
	if [[ ! "$key" =~ ^[a-zA-Z0-9!#\$%\&\'*+.\^_\`\|~-]+$ ]]; then
		return 1
	fi

	return 0
}

# Validate headers JSON object
#
# Headers must be a JSON object where all values are strings
#
# Source: MCP specification - HTTP transport headers
validate_headers() {
	local headers_json="$1"

	# Empty or null is invalid (caller should check if headers exist first)
	if [ -z "$headers_json" ] || [ "$headers_json" = "null" ]; then
		return 1
	fi

	# Must be valid JSON
	if ! echo "$headers_json" | jq empty 2>/dev/null; then
		return 1
	fi

	# Must be an object
	local json_type
	json_type=$(echo "$headers_json" | jq -r 'type' 2>/dev/null)
	if [ "$json_type" != "object" ]; then
		return 1
	fi

	# All values must be strings
	local has_non_string
	has_non_string=$(echo "$headers_json" | jq '[.[] | type != "string"] | any' 2>/dev/null)
	if [ "$has_non_string" = "true" ]; then
		return 1
	fi

	return 0
}

# Check if a field name is recognized
#
# Returns exit code 0 if field is known, 1 if unknown
# For unknown fields, outputs a warning to stderr but does NOT fail
#
# Source: Spec 01 - Unknown field handling
validate_unknown_field() {
	local field_name="$1"

	# Check if field is in the known list
	for known in "${KNOWN_FIELDS[@]}"; do
		if [ "$field_name" = "$known" ]; then
			return 0
		fi
	done

	return 1
}

# Find closest match for unknown field (typo detection)
#
# Uses simple substring matching to suggest corrections
# Returns the closest field name or empty string
find_closest_field() {
	local unknown="$1"
	local best_match=""
	local best_score=0

	for known in "${KNOWN_FIELDS[@]}"; do
		# Simple scoring: count matching characters
		local score=0
		local len=${#unknown}
		for ((i = 0; i < len; i++)); do
			local char="${unknown:$i:1}"
			if [[ "$known" == *"$char"* ]]; then
				((score++))
			fi
		done

		# Bonus for similar length
		local len_diff=$((${#known} - ${#unknown}))
		if [ $len_diff -lt 0 ]; then
			len_diff=$((-len_diff))
		fi
		if [ $len_diff -le 2 ]; then
			((score += 2))
		fi

		# Bonus for same first letter
		if [ "${known:0:1}" = "${unknown:0:1}" ]; then
			((score += 3))
		fi

		if [ $score -gt $best_score ]; then
			best_score=$score
			best_match="$known"
		fi
	done

	# Only suggest if score is reasonable (at least half the characters match)
	local threshold=$((${#unknown} / 2 + 2))
	if [ $best_score -ge $threshold ]; then
		echo "$best_match"
	fi
}

# Warn about unknown fields in configuration
#
# Outputs warning to stderr but allows processing to continue (exit 0)
# Per Spec 08: Unknown fields generate warnings, not errors
warn_unknown_fields() {
	local config="$1"

	# Get all field names from the config
	local fields
	fields=$(echo "$config" | jq -r 'keys[]' 2>/dev/null)

	while IFS= read -r field; do
		if [ -n "$field" ] && ! validate_unknown_field "$field"; then
			echo "Warning: Unknown field '$field' in configuration" >&2
			echo "Valid fields: ${KNOWN_FIELDS[*]}" >&2

			local suggestion
			suggestion=$(find_closest_field "$field")
			if [ -n "$suggestion" ]; then
				echo "Did you mean: $suggestion" >&2
			fi
			echo "" >&2
		fi
	done <<<"$fields"
}

# ==============================================================================
# Scope Validation Functions (Spec 04)
# ==============================================================================

# Validate scope for Claude Code
#
# Claude Code supports scope with values: local, project, user
# Case-sensitive (lowercase only)
validate_scope_for_claude() {
	local scope="$1"

	# Empty scope is valid (means "don't include scope flag")
	if [ -z "$scope" ]; then
		return 0
	fi

	# Must be one of the valid values (case-sensitive)
	if [[ ! "$scope" =~ ^(local|project|user)$ ]]; then
		return 1
	fi

	return 0
}

# Reject scope for Amp
#
# Amp does NOT support scope field - always uses global amp.mcpServers
# If scope is provided, returns error with helpful message
reject_scope_for_amp() {
	local scope="$1"

	# Empty scope is OK - no action needed
	if [ -z "$scope" ]; then
		return 0
	fi

	# Any scope value for Amp is an error
	cat >&2 <<EOF
Error: 'scope' field is not supported by Amp

Reason: Amp stores all MCP server configurations in 'amp.mcpServers' and does not support per-scope organization like Claude Code does.

Solution: Remove the 'scope' field from your configuration. If you're migrating from Claude Code to Amp, simply omit this field.

For more information, see:
- Amp Documentation: https://ampcode.com/manual#mcp
- Claude Code Documentation: https://code.claude.com/docs/en/mcp
EOF
	return 1
}

# Generate scope flag for CLI command
#
# Returns --scope <value> for Claude Code when scope is provided
# Returns empty string for Amp or when no scope
generate_scope_flag() {
	local scope="$1"
	local cli_type="$2"

	# No scope provided - no flag
	if [ -z "$scope" ]; then
		echo ""
		return 0
	fi

	# Amp doesn't support scope (should have been rejected earlier)
	if [ "$cli_type" = "amp" ]; then
		echo ""
		return 0
	fi

	# Claude Code - return the flag
	echo "--scope $scope"
	return 0
}

# ==============================================================================
# includeTools Validation (Spec 05) - Amp Only
# ==============================================================================

# Validate a single glob pattern
#
# Valid patterns can contain:
#   - Alphanumeric characters, underscores, hyphens
#   - Wildcards: * (any sequence), ? (single char)
#   - Character classes: [abc], [!abc], [a-z]
#
# Invalid patterns:
#   - Empty string
#   - Brace expansion: {a,b}
#   - Recursive wildcard: **
#   - Unclosed brackets
validate_glob_pattern() {
	local pattern="$1"

	# Empty pattern is invalid
	if [ -z "$pattern" ]; then
		return 1
	fi

	# Check for brace expansion (not supported)
	if [[ "$pattern" == *"{"* ]] || [[ "$pattern" == *"}"* ]]; then
		echo "brace expansion not supported" >&2
		return 1
	fi

	# Check for recursive wildcard (not supported)
	if [[ "$pattern" == *"**"* ]]; then
		echo "recursive wildcard not supported" >&2
		return 1
	fi

	# Check for unclosed brackets
	local open_count="${pattern//[^\[]/}"
	local close_count="${pattern//[^\]]/}"
	if [ ${#open_count} -ne ${#close_count} ]; then
		echo "unclosed bracket" >&2
		return 1
	fi

	return 0
}

# Validate includeTools array
#
# Must be an array of valid glob pattern strings
# Only valid for stdio transport
validate_includeTools() {
	local include_tools_json="$1"

	# Empty or null is valid (means field not provided)
	if [ -z "$include_tools_json" ] || [ "$include_tools_json" = "null" ]; then
		return 0
	fi

	# Must be an array
	if ! validate_is_array "$include_tools_json"; then
		echo "Error: 'includeTools' must be an array of strings" >&2
		return 1
	fi

	# All elements must be strings
	if ! validate_array_of_strings "$include_tools_json"; then
		echo "Error: 'includeTools' array must contain only strings" >&2
		return 1
	fi

	# Validate each pattern
	local count
	count=$(echo "$include_tools_json" | jq 'length')
	for ((i = 0; i < count; i++)); do
		local pattern
		pattern=$(echo "$include_tools_json" | jq -r ".[$i]")
		if ! validate_glob_pattern "$pattern" 2>/dev/null; then
			local reason
			reason=$(validate_glob_pattern "$pattern" 2>&1)
			echo "Error: Invalid glob pattern '$pattern': $reason" >&2
			return 1
		fi
	done

	return 0
}

# Validate includeTools for transport type
#
# includeTools is only valid for stdio transport
validate_includeTools_for_transport() {
	local include_tools_json="$1"
	local transport="$2"

	# If includeTools not provided, always valid
	if [ -z "$include_tools_json" ] || [ "$include_tools_json" = "null" ]; then
		return 0
	fi

	# Only valid for stdio transport
	if [ "$transport" != "stdio" ]; then
		cat >&2 <<EOF
Error: 'includeTools' is only valid for stdio transport, not $transport

Reason: includeTools filters tools from local MCP servers. Remote HTTP/SSE servers expose fixed tool sets.

Solution: Remove 'includeTools' field or change transport to stdio
EOF
		return 1
	fi

	return 0
}

# ==============================================================================
# Header Formatting Functions (Spec 03)
# ==============================================================================

# Escape special characters in header values for shell safety
#
# Escapes: backslashes, double quotes, dollar signs
escape_header_value() {
	local value="$1"

	# Escape backslashes first (must be done first to avoid double escaping)
	value="${value//\\/\\\\}"

	# Escape double quotes
	value="${value//\"/\\\"}"

	# Escape dollar signs to prevent shell expansion
	value="${value//\$/\\\$}"

	echo "$value"
}

# Format headers for Claude Code CLI
#
# Claude Code uses colon-space separator: --header "Key: Value"
# Each header is output on a separate line
format_headers_claude() {
	local headers_json="$1"

	# Empty headers - no output
	if [ -z "$headers_json" ] || [ "$headers_json" = "{}" ] || [ "$headers_json" = "null" ]; then
		return 0
	fi

	# Iterate through each header
	while IFS= read -r line; do
		local key
		local value
		key=$(echo "$line" | jq -r '.key')
		value=$(echo "$line" | jq -r '.value')

		# Escape special characters in value
		local escaped_value
		escaped_value=$(escape_header_value "$value")

		# Claude format: --header "Key: Value" (colon with space)
		echo "--header \"$key: $escaped_value\""
	done < <(echo "$headers_json" | jq -c 'to_entries[]' 2>/dev/null)
}

# Format headers for Amp CLI
#
# Amp uses equals separator: --header "Key=Value"
# Each header is output on a separate line
format_headers_amp() {
	local headers_json="$1"

	# Empty headers - no output
	if [ -z "$headers_json" ] || [ "$headers_json" = "{}" ] || [ "$headers_json" = "null" ]; then
		return 0
	fi

	# Iterate through each header
	while IFS= read -r line; do
		local key
		local value
		key=$(echo "$line" | jq -r '.key')
		value=$(echo "$line" | jq -r '.value')

		# Escape special characters in value
		local escaped_value
		escaped_value=$(escape_header_value "$value")

		# Amp format: --header "Key=Value" (equals, no space)
		echo "--header \"$key=$escaped_value\""
	done < <(echo "$headers_json" | jq -c 'to_entries[]' 2>/dev/null)
}

# Format headers for the specified CLI type
#
# Routes to the appropriate formatting function based on CLI type
format_headers() {
	local headers_json="$1"
	local cli_type="$2"

	case "$cli_type" in
	claude)
		format_headers_claude "$headers_json"
		;;
	amp)
		format_headers_amp "$headers_json"
		;;
	*)
		echo "Error: Invalid CLI type '$cli_type' for header formatting" >&2
		return 1
		;;
	esac

	return 0
}

# ==============================================================================
# Transport Handling Functions (Spec 02)
# ==============================================================================

# Validate transport type is supported by the specified CLI
#
# Both Claude Code and Amp support all three transport types
# The difference is how they handle them:
#   - Claude Code: Requires explicit --transport flag
#   - Amp: Auto-detects from server response
validate_transport_for_cli() {
	local transport="$1"
	local cli_type="$2"

	# First validate transport type itself
	if ! validate_transport_type "$transport"; then
		return 1
	fi

	# Validate CLI type
	if [[ ! "$cli_type" =~ ^(claude|amp)$ ]]; then
		return 1
	fi

	# Both CLIs support all three transports
	return 0
}

# Generate transport flag for CLI command
#
# Claude Code: returns "--transport <type>"
# Amp: returns empty string (no flag needed, auto-detection)
generate_transport_flag() {
	local transport="$1"
	local cli_type="$2"

	case "$cli_type" in
	claude)
		echo "--transport $transport"
		;;
	amp)
		# Amp auto-detects transport, no flag needed
		echo ""
		;;
	*)
		echo ""
		;;
	esac
}

# ==============================================================================
# CLI Routing Functions (Spec 06)
# ==============================================================================

# Determine the active CLI type
#
# Priority: flag > saved preference > default (claude)
determine_cli_type() {
	local cli_from_flag="$1"
	local saved_preference="$2"

	# Flag takes priority
	if [ -n "$cli_from_flag" ]; then
		echo "$cli_from_flag"
		return 0
	fi

	# Use saved preference if available
	if [ -n "$saved_preference" ]; then
		echo "$saved_preference"
		return 0
	fi

	# Default to claude
	echo "claude"
	return 0
}

# Validate CLI type is supported
validate_cli_type() {
	local cli_type="$1"

	# Empty is invalid
	if [ -z "$cli_type" ]; then
		return 1
	fi

	# Must be one of the supported types
	if [[ ! "$cli_type" =~ ^(claude|amp)$ ]]; then
		return 1
	fi

	return 0
}

# ==============================================================================
# CLI Preference Management
# ==============================================================================

# Load CLI preference from config file
#
# Attempts to load the last-used CLI preference from the configuration file.
# Searches in this order:
#   1. $XDG_CONFIG_HOME/mcp-commandline/config (XDG base directory standard)
#   2. ~/.mcp-commandline-config (fallback location)
#
# Returns:
#   0 and outputs CLI type (claude or amp) on stdout if config exists and is valid
#   1 if config file doesn't exist or cannot be read
#
load_cli_preference() {
	local config_file

	# Try XDG config directory first
	if [ -n "${XDG_CONFIG_HOME:-}" ]; then
		config_file="$XDG_CONFIG_HOME/mcp-commandline/config"
	else
		config_file="$HOME/.config/mcp-commandline/config"
	fi

	# Check XDG location first
	if [ -f "$config_file" ]; then
		# Source the config file and extract CLI_TYPE variable
		# shellcheck disable=SC1090
		if source "$config_file" 2>/dev/null && [ -n "${CLI_TYPE:-}" ]; then
			echo "$CLI_TYPE"
			return 0
		fi
	fi

	# Fallback to alternate location
	config_file="$HOME/.mcp-commandline-config"
	if [ -f "$config_file" ]; then
		# shellcheck disable=SC1090
		if source "$config_file" 2>/dev/null && [ -n "${CLI_TYPE:-}" ]; then
			echo "$CLI_TYPE"
			return 0
		fi
	fi

	return 1
}

# Save CLI preference to config file
#
# Saves the selected CLI type to the configuration file for future invocations.
# Creates the config directory if needed (respecting XDG base directory standard).
#
# Parameters:
#   $1 (cli_type): The CLI type to save (claude or amp)
#
save_cli_preference() {
	local cli_type="$1"
	local config_file
	local config_dir

	# Determine config location (prefer XDG standard)
	if [ -n "${XDG_CONFIG_HOME:-}" ]; then
		config_dir="$XDG_CONFIG_HOME/mcp-commandline"
		config_file="$config_dir/config"
	else
		config_dir="$HOME/.config/mcp-commandline"
		config_file="$config_dir/config"
	fi

	# Create config directory if it doesn't exist
	mkdir -p "$config_dir" 2>/dev/null || {
		# If XDG fails, try fallback location
		config_file="$HOME/.mcp-commandline-config"
	}

	# Write the config file
	if ! echo "CLI_TYPE=$cli_type" >"$config_file" 2>/dev/null; then
		# Silently fail if we can't write config - don't interrupt user's command
		return 1
	fi

	return 0
}

# Infer transport type from configuration structure
#
# When the 'type' field is not explicitly provided, this function determines the
# transport type by examining the configuration structure:
#
# Inference Rules:
#   - If 'command' is present and 'url' is absent → stdio transport
#   - If 'url' is present and 'command' is absent → http transport (default remote)
#   - If both 'command' and 'url' are present → ambiguous (error, requires explicit type)
#   - If neither is present → no inference possible (error, requires explicit type)
#
# Parameters:
#   $1 (config): Server configuration as JSON string
#
# Returns:
#   0 and outputs inferred type on stdout if successful
#   1 if inference fails (ambiguous or insufficient data)
#
infer_transport_type() {
	local config="$1"

	# Check which transport-defining fields are present
	local has_command
	has_command=$(echo "$config" | jq 'has("command")' 2>/dev/null)
	local has_url
	has_url=$(echo "$config" | jq 'has("url")' 2>/dev/null)

	# Both present → ambiguous, require explicit type
	if [ "$has_command" = "true" ] && [ "$has_url" = "true" ]; then
		return 1
	fi

	# Only command present → stdio transport
	if [ "$has_command" = "true" ]; then
		echo "stdio"
		return 0
	fi

	# Only url present → http transport (default for remote transports)
	if [ "$has_url" = "true" ]; then
		echo "http"
		return 0
	fi

	# Neither present → inference failed, type required
	return 1
}

# Get the base MCP add command for the selected CLI
#
# Returns the appropriate base command string for the selected CLI type.
# Supports: claude (uses 'claude mcp add'), amp (uses 'amp mcp add')
#
# Parameters:
#   $1 (cli_type): The CLI type (claude or amp)
#
# Returns:
#   0 and outputs the base command string
#   1 if CLI type is invalid
#
get_cli_command() {
	local cli_type="$1"

	case "$cli_type" in
	claude)
		echo "claude mcp add"
		return 0
		;;
	amp)
		echo "amp mcp add"
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# ==============================================================================
# Command Generation (Spec 07)
# ==============================================================================

# Quote an argument if it contains special characters
#
# Per Spec 07 (Option B): Quote arguments with spaces OR special characters
quote_argument() {
	local arg="$1"

	# Check if quoting is needed (spaces or special characters)
	if [[ "$arg" =~ [[:space:]\"\'\$\`\\] ]]; then
		# Escape backslashes first
		arg="${arg//\\/\\\\}"
		# Escape double quotes
		arg="${arg//\"/\\\"}"
		# Escape dollar signs
		arg="${arg//\$/\\\$}"
		# Wrap in quotes
		echo "\"$arg\""
	else
		echo "$arg"
	fi
}

# Function to process a single server and generate command
#
# This function validates a single MCP server configuration and generates the
# appropriate MCP add command for the selected CLI. All schema validation is performed here.
#
# Parameters:
#   $1 (name): Server name - used as unique identifier in configuration
#   $2 (type): Transport type - must be one of: http, sse, stdio
#   $3 (config): Server configuration as JSON string
#   $4 (cli_type): CLI type - must be one of: claude, amp
#
process_server() {
	local name="$1"
	local type="$2"
	local config="$3"
	local cli_type="$4"

	# Warn about unknown fields (non-fatal)
	warn_unknown_fields "$config"

	# Validate server name using MCP schema naming rules
	if ! validate_server_name "$name"; then
		cat >&2 <<EOF
Error: Invalid server name
Details: '$name' contains invalid characters
Suggestion: Use only letters, numbers, hyphens, and underscores
EOF
		exit 1
	fi

	# Validate transport type enum
	if ! validate_transport_type "$type"; then
		cat >&2 <<EOF
Error: Invalid transport type
Details: '$type' is not supported
Suggestion: Use one of: http, sse, stdio
EOF
		exit 1
	fi

	# Extract scope early for CLI-specific validation
	local scope
	scope=$(echo "$config" | jq -r '.scope // empty')

	# CLI-specific scope validation (Spec 04)
	if [ "$cli_type" = "amp" ]; then
		# Amp does NOT support scope - reject if provided
		if ! reject_scope_for_amp "$scope"; then
			exit 1
		fi
	else
		# Claude Code - validate scope if provided
		if [ -n "$scope" ]; then
			if ! validate_scope_for_claude "$scope"; then
				cat >&2 <<EOF
Error: Invalid scope value
Details: '$scope' is not valid
Suggestion: 'scope' must be one of: local, project, user
EOF
				exit 1
			fi
		fi
	fi

	# Validate includeTools for Amp (Spec 05)
	local include_tools
	include_tools=$(echo "$config" | jq '.includeTools // empty')
	if [ -n "$include_tools" ] && [ "$include_tools" != "null" ]; then
		# Validate transport compatibility
		if ! validate_includeTools_for_transport "$include_tools" "$type"; then
			exit 1
		fi
		# Validate the patterns themselves
		if ! validate_includeTools "$include_tools"; then
			exit 1
		fi
	fi

	# Get the appropriate CLI command based on CLI type
	local cli_base_cmd
	if ! cli_base_cmd=$(get_cli_command "$cli_type"); then
		cat >&2 <<EOF
Error: Invalid CLI type
Details: '$cli_type' is not supported
Suggestion: Must be: claude or amp
EOF
		exit 1
	fi

	# Build command based on transport type
	if [[ "$type" == "http" ]] || [[ "$type" == "sse" ]]; then
		# ==== HTTP/SSE Transport Command Building ====

		# Extract and validate URL
		local url
		url=$(echo "$config" | jq -r '.url // empty')

		if [ -z "$url" ]; then
			cat >&2 <<EOF
Error: Missing required field
Details: 'url' field is required for $type transport
Suggestion: Provide a valid URL, e.g., "url": "https://api.example.com"
EOF
			exit 1
		fi

		if ! validate_url "$url"; then
			cat >&2 <<EOF
Error: Invalid URL format
Details: '$url' is not a valid URL
Suggestion: URL must start with http:// or https://, e.g., https://api.example.com
EOF
			exit 1
		fi

		# Start building command
		# Order for HTTP/SSE: base → transport → name → URL → headers → scope
		# (Transport flag comes before name in Claude Code)
		local transport_flag
		transport_flag=$(generate_transport_flag "$type" "$cli_type")
		if [ -n "$transport_flag" ]; then
			cmd="$cli_base_cmd $transport_flag $name $url"
		else
			cmd="$cli_base_cmd $name $url"
		fi

		# Process headers
		local headers
		headers=$(echo "$config" | jq '.headers // empty')
		if [ -n "$headers" ] && [ "$headers" != "null" ] && [ "$headers" != "{}" ]; then
			# Validate headers structure
			if ! validate_headers "$headers"; then
				cat >&2 <<EOF
Error: Invalid headers format
Details: 'headers' must be a JSON object with string values
Suggestion: Use format: {"Key": "Value"}
EOF
				exit 1
			fi

			# Format and add headers based on CLI type
			local header_flags
			header_flags=$(format_headers "$headers" "$cli_type")
			if [ -n "$header_flags" ]; then
				while IFS= read -r flag; do
					if [ -n "$flag" ]; then
						cmd="$cmd $flag"
					fi
				done <<<"$header_flags"
			fi
		fi

		# Add scope flag (Claude Code only)
		local scope_flag
		scope_flag=$(generate_scope_flag "$scope" "$cli_type")
		if [ -n "$scope_flag" ]; then
			cmd="$cmd $scope_flag"
		fi

	elif [[ "$type" == "stdio" ]]; then
		# ==== Stdio Transport Command Building ====

		# Extract and validate command
		local server_command
		server_command=$(echo "$config" | jq -r '.command // empty')

		if [ -z "$server_command" ]; then
			cat >&2 <<EOF
Error: Missing required field
Details: 'command' field is required for stdio transport
Suggestion: Provide the command to execute, e.g., "command": "python"
EOF
			exit 1
		fi

		# Start building command
		# Order for Claude Code Stdio: base → transport → name → scope → -- → command → args → env
		# Order for Amp Stdio: base → name → stdio → command → args → env
		if [ "$cli_type" = "claude" ]; then
			local transport_flag
			transport_flag=$(generate_transport_flag "stdio" "$cli_type")
			cmd="$cli_base_cmd $transport_flag $name"

			# Add scope BEFORE the -- separator (Claude only)
			local scope_flag
			scope_flag=$(generate_scope_flag "$scope" "$cli_type")
			if [ -n "$scope_flag" ]; then
				cmd="$cmd $scope_flag"
			fi
			# Add -- separator (Claude Code only)
			cmd="$cmd --"
		else
			# Amp: base → name → stdio → command
			cmd="$cli_base_cmd $name stdio"
		fi

		# Add the server command (quote if needed)
		local quoted_command
		quoted_command=$(quote_argument "$server_command")
		cmd="$cmd $quoted_command"

		# Process args
		local args
		args=$(echo "$config" | jq '.args // empty')
		if [ -n "$args" ] && [ "$args" != "null" ] && [ "$args" != "[]" ]; then
			# Validate args is an array of strings
			if ! validate_is_array "$args"; then
				cat >&2 <<EOF
Error: Invalid arguments format
Details: 'args' must be an array
Suggestion: Use format: ["arg1", "arg2"]
EOF
				exit 1
			fi

			if ! validate_array_of_strings "$args"; then
				cat >&2 <<EOF
Error: Invalid arguments content
Details: 'args' array must contain only strings
Suggestion: Each element must be a string, e.g., ["-m", "mcp.server"]
EOF
				exit 1
			fi

			# Add each argument
			while IFS= read -r arg; do
				local quoted_arg
				quoted_arg=$(quote_argument "$arg")
				cmd="$cmd $quoted_arg"
			done < <(echo "$config" | jq -r '.args[]')
		fi

		# Process environment variables (appended at end for both CLIs)
		local env_vars
		env_vars=$(echo "$config" | jq '.env // empty')
		if [ -n "$env_vars" ] && [ "$env_vars" != "null" ] && [ "$env_vars" != "{}" ]; then
			# Validate env is an object
			if ! validate_is_object "$env_vars"; then
				cat >&2 <<EOF
Error: Invalid environment variables format
Details: 'env' must be a JSON object
Suggestion: Use format: {"VAR": "value"}
EOF
				exit 1
			fi

			# Add each environment variable
			while IFS= read -r line; do
				local key value
				key=$(echo "$line" | jq -r '.key')
				value=$(echo "$line" | jq -r '.value')

				# Validate environment variable name
				if ! validate_env_var_name "$key"; then
					cat >&2 <<EOF
Error: Invalid environment variable name
Details: '$key' is not a valid variable name
Suggestion: Must start with letter or underscore, contain only alphanumeric and underscores
EOF
					exit 1
				fi

				# Quote the value if needed
				local quoted_value
				quoted_value=$(quote_argument "$value")
				# Remove outer quotes for env var format
				quoted_value="${quoted_value#\"}"
				quoted_value="${quoted_value%\"}"
				cmd="$cmd $key=\"$quoted_value\""
			done < <(echo "$config" | jq -c '.env | to_entries[] | {key: .key, value: .value}')
		fi
	fi

	# Execute or print the command
	if [ "$EXECUTE" = true ]; then
		eval "$cmd"
	else
		echo "$cmd"
	fi
}

# Parse command line options
EXECUTE=false
CLI_TYPE=""
JSON_INPUT=""

while [[ $# -gt 0 ]]; do
	case $1 in
	-c | --cli)
		if [[ $# -lt 2 ]]; then
			echo "Error: --cli option requires a value (claude or amp)" >&2
			exit 1
		fi
		CLI_TYPE="$2"
		shift 2
		;;
	-x | --execute)
		EXECUTE=true
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		JSON_INPUT="$1"
		shift
		;;
	esac
done

# Validate CLI type if provided
if [ -n "$CLI_TYPE" ]; then
	if [[ ! "$CLI_TYPE" =~ ^(claude|amp)$ ]]; then
		echo "Error: Invalid CLI type '$CLI_TYPE'. Must be: claude, amp" >&2
		exit 1
	fi
else
	# Load CLI preference from config file, default to claude if not found
	CLI_TYPE=$(load_cli_preference || echo "claude")
fi

# Get JSON input from argument or stdin
if [ -z "$JSON_INPUT" ]; then
	if [ -t 0 ]; then
		echo "Error: No JSON input provided" >&2
		usage
	fi
	JSON_INPUT=$(cat)
fi

# Validate JSON syntax
# Schema: Input must be valid JSON (either flat format or Claude Desktop format)
# This is the first validation - all subsequent operations assume valid JSON
# Source: RFC 8259 - JSON specification
if ! echo "$JSON_INPUT" | jq empty 2>/dev/null; then
	echo "Error: Invalid JSON input" >&2
	exit 1
fi

# Validate jq availability
# Requirement: jq is required for JSON parsing and validation
if ! command -v jq &>/dev/null; then
	echo "Error: jq is required but not installed" >&2
	exit 1
fi

# Detect which JSON format is being used
# Schema supports two formats:
# 1. Flat format: {"name": "...", "type": "...", ...}
# 2. Claude Desktop format: {"mcpServers": {"server-name": {...}}}
# Source: MCP specification - configuration format variations
has_mcpServers=$(echo "$JSON_INPUT" | jq 'has("mcpServers")' 2>/dev/null || echo "false")

if [ "$has_mcpServers" = "true" ]; then
	# Format 2: Claude Desktop config - process each server
	servers=$(echo "$JSON_INPUT" | jq -r '.mcpServers | keys[]')

	if [ -z "$servers" ]; then
		echo "Error: No servers found in mcpServers object" >&2
		exit 1
	fi

	# Process each server
	while IFS= read -r name; do
		# Extract server config
		server_config=$(echo "$JSON_INPUT" | jq ".mcpServers[\"$name\"]")
		type=$(echo "$server_config" | jq -r '.type // empty')

		# If type not explicitly provided, attempt to infer from configuration structure
		if [ -z "$type" ]; then
			if inferred=$(infer_transport_type "$server_config"); then
				type="$inferred"
			fi
		fi

		if [ -z "$type" ]; then
			echo "Error: 'type' field is required for server '$name'" >&2
			echo "" >&2
			echo "Reason: Cannot determine transport type from configuration structure." >&2
			echo "" >&2
			echo "To fix, either:" >&2
			echo "  1. Add explicit 'type' field: \"type\": \"http\" or \"type\": \"stdio\"" >&2
			echo "  2. Use only 'url' field (will infer http): {\"name\":\"...\",\"url\":\"https://...\"}" >&2
			echo "  3. Use only 'command' field (will infer stdio): {\"name\":\"...\",\"command\":\"npx\",\"args\":[...]}" >&2
			echo "" >&2
			echo "Note: If both 'command' and 'url' are present, 'type' must be explicit." >&2
			exit 1
		fi

		# Process this server
		process_server "$name" "$type" "$server_config" "$CLI_TYPE"
	done <<<"$servers"
else
	# Format 1: Flat format - extract name and config
	name=$(echo "$JSON_INPUT" | jq -r '.name // empty')
	type=$(echo "$JSON_INPUT" | jq -r '.type // empty')

	if [ -z "$name" ]; then
		echo "Error: 'name' field is required" >&2
		exit 1
	fi

	# If type not explicitly provided, attempt to infer from configuration structure
	if [ -z "$type" ]; then
		if inferred=$(infer_transport_type "$JSON_INPUT"); then
			type="$inferred"
		fi
	fi

	if [ -z "$type" ]; then
		echo "Error: 'type' field is required for server '$name'" >&2
		echo "" >&2
		echo "Reason: Cannot determine transport type from configuration structure." >&2
		echo "" >&2
		echo "To fix, either:" >&2
		echo "  1. Add explicit 'type' field: \"type\": \"http\" or \"type\": \"stdio\"" >&2
		echo "  2. Use only 'url' field (will infer http): {\"name\":\"...\",\"url\":\"https://...\"}" >&2
		echo "  3. Use only 'command' field (will infer stdio): {\"name\":\"...\",\"command\":\"npx\",\"args\":[...]}" >&2
		echo "" >&2
		echo "Note: If both 'command' and 'url' are present, 'type' must be explicit." >&2
		exit 1
	fi

	# Process this server
	process_server "$name" "$type" "$JSON_INPUT" "$CLI_TYPE"
fi

# Save the CLI preference for next invocation
save_cli_preference "$CLI_TYPE"
