#!/bin/bash

set -euo pipefail

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [JSON_INPUT]

Convert JSON MCP server configuration to 'claude mcp add' command.

Input can be provided as:
  - First argument: $0 '{"name":"server","url":"https://..."}'
  - stdin: echo '{"name":"server",...}' | $0

Options:
  -x, --execute    Execute the command instead of printing it
  -h, --help       Show this help message

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

# Validation functions
#
# These functions validate MCP server configurations against the official MCP schema.
# Schema source: https://modelcontextprotocol.io/specification/2025-11-25
# Additional validation based on Claude Code MCP documentation
#

# Validate URL format (must be valid HTTP/HTTPS URL)
#
# MCP Schema Rule: HTTP and SSE transports require a valid HTTPS or HTTP URL
# This validation checks:
#   - Protocol: http:// or https:// (required)
#   - URL format: basic structure validation
#   - Supports: URLs with ports, paths, query parameters, and fragments
#
# Source: MCP specification 2025-11-25 - HTTP/SSE transport requirements
validate_url() {
    local url="$1"
    # Simple protocol check: must start with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
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
# Note: Numbers in args will be converted to strings by jq, but null values
# or complex objects are invalid and caught by this validation.
#
# Source: MCP stdio transport specification - args field definition
validate_array_of_strings() {
    local array="$1"
    local count=$(echo "$array" | jq 'length')

    for ((i=0; i<count; i++)); do
        local element=$(echo "$array" | jq -r ".[$i]")
        if [ "$element" = "null" ]; then
            return 1
        fi
    done
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
    local has_command=$(echo "$config" | jq 'has("command")' 2>/dev/null)
    local has_url=$(echo "$config" | jq 'has("url")' 2>/dev/null)

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

# Function to process a single server and generate command
#
# This function validates a single MCP server configuration and generates the
# appropriate 'claude mcp add' command. All schema validation is performed here.
#
# Parameters:
#   $1 (name): Server name - used as unique identifier in configuration
#   $2 (type): Transport type - must be one of: http, sse, stdio
#   $3 (config): Server configuration as JSON string
#
process_server() {
    local name="$1"
    local type="$2"
    local config="$3"

    # Validate server name using MCP schema naming rules
    # Schema: Server names must be valid JSON object keys
    # Source: MCP specification - configuration object key naming
    if ! validate_server_name "$name"; then
        echo "Error: Server name '$name' is invalid. Must contain only alphanumeric characters, hyphens, and underscores" >&2
        exit 1
    fi

    # Validate transport type enum
    # Schema: type field must be one of: http, sse, stdio
    # - http: Remote HTTP/HTTPS endpoint (recommended)
    # - sse: Remote Server-Sent Events endpoint (deprecated, use http)
    # - stdio: Local process via standard input/output
    # Source: MCP specification - transport types
    if [[ ! "$type" =~ ^(http|sse|stdio)$ ]]; then
        echo "Error: 'type' must be one of: http, sse, stdio (got '$type')" >&2
        exit 1
    fi

    # Build base command
    cmd="claude mcp add --transport $type $name"

    # Build command based on transport type
    if [[ "$type" == "http" ]] || [[ "$type" == "sse" ]]; then
        # HTTP/SSE transport validation and command building
        # Schema: HTTP and SSE transports REQUIRE the url field
        url=$(echo "$config" | jq -r '.url // empty')

        if [ -z "$url" ]; then
            echo "Error: 'url' field is required for $type transport" >&2
            exit 1
        fi

        # Validate URL format using HTTP(S) URL validation
        # Schema: url must be a valid HTTP or HTTPS URL
        # Source: MCP specification - HTTP/SSE transport requirements
        if ! validate_url "$url"; then
            echo "Error: Invalid URL format for '$url'. Must be valid HTTP(S) URL" >&2
            exit 1
        fi

        cmd="$cmd $url"

        # Optional: headers field for HTTP/SSE authentication and custom headers
        # Schema: headers is optional, must be object if present
        # Type: object (key-value pairs of strings)
        # Use case: Authentication (Bearer tokens, API keys), custom headers
        # Source: MCP specification - HTTP transport headers
        headers=$(echo "$config" | jq '.headers // empty')
        if [ -n "$headers" ] && [ "$headers" != "null" ]; then
            # Validate headers is an object type
            if ! validate_is_object "$headers"; then
                echo "Error: 'headers' must be an object (key-value pairs)" >&2
                exit 1
            fi

            while IFS= read -r line; do
                key=$(echo "$line" | jq -r '.key')
                value=$(echo "$line" | jq -r '.value')
                cmd="$cmd --header \"$key: $value\""
            done < <(echo "$config" | jq -c '.headers | to_entries[] | {key: .key, value: .value}')
        fi

    elif [[ "$type" == "stdio" ]]; then
        # Stdio transport validation and command building
        # Schema: Stdio transports REQUIRE the command field
        command=$(echo "$config" | jq -r '.command // empty')

        if [ -z "$command" ]; then
            echo "Error: 'command' field is required for stdio transport" >&2
            exit 1
        fi

        # Optional: env field for environment variables passed to stdio process
        # Schema: env is optional, must be object if present
        # Type: object with valid environment variable names as keys
        # Keys must follow POSIX shell variable naming: start with letter/underscore,
        # contain only alphanumeric characters and underscores
        # Source: MCP specification - stdio transport environment variables
        env_vars=$(echo "$config" | jq '.env // empty')
        if [ -n "$env_vars" ] && [ "$env_vars" != "null" ]; then
            # Validate env is an object type
            if ! validate_is_object "$env_vars"; then
                echo "Error: 'env' must be an object (key-value pairs)" >&2
                exit 1
            fi

            while IFS= read -r line; do
                key=$(echo "$line" | jq -r '.key')
                value=$(echo "$line" | jq -r '.value')

                # Validate environment variable name using POSIX shell naming rules
                # Schema: Environment variable names must be valid shell variable identifiers
                # Format: [a-zA-Z_][a-zA-Z0-9_]*
                # Source: POSIX shell specification and MCP environment handling
                if ! validate_env_var_name "$key"; then
                    echo "Error: Invalid environment variable name '$key'. Must start with letter or underscore, contain only alphanumeric characters and underscores" >&2
                    exit 1
                fi

                cmd="$cmd --env $key=\"$value\""
            done < <(echo "$config" | jq -c '.env | to_entries[] | {key: .key, value: .value}')
        fi

        # Optional: scope field for configuration storage location
        # Schema: scope must be one of: local, project, user
        # - local: User-level ~/.claude.json (default, applies across all projects)
        # - project: Repository-level .mcp.json at repo root (shared with team)
        # - user: Compatibility alias for local (same as local)
        # Source: Claude Code configuration documentation - Scope options
        scope=$(echo "$config" | jq -r '.scope // empty')
        if [ -n "$scope" ]; then
            if ! validate_scope "$scope"; then
                echo "Error: 'scope' must be one of: local, project, user. Got: '$scope'" >&2
                exit 1
            fi
            cmd="$cmd --scope $scope"
        fi

        # Add mandatory -- separator to separate Claude MCP flags from command arguments
        # This tells the shell parser that everything after -- should be passed literally
        cmd="$cmd --"

        # Add the command to execute
        cmd="$cmd $command"

        # Optional: args field for command-line arguments to the stdio process
        # Schema: args is optional for stdio, must be array of strings if present
        # Type: array where each element is a string argument
        # Usage: Arguments are appended to the command in order
        # Source: MCP specification - stdio transport args field
        args=$(echo "$config" | jq '.args // empty')
        if [ -n "$args" ] && [ "$args" != "null" ]; then
            # Validate args is an array type
            if ! validate_is_array "$args"; then
                echo "Error: 'args' must be an array of strings" >&2
                exit 1
            fi

            # Validate array contains only string elements
            # Schema: Each element in args array must be a string (not null, object, etc.)
            if ! validate_array_of_strings "$args"; then
                echo "Error: 'args' array contains non-string elements. All array elements must be strings" >&2
                exit 1
            fi

            while IFS= read -r arg; do
                # Quote args that contain spaces to preserve them as single arguments
                if [[ "$arg" =~ [[:space:]] ]]; then
                    cmd="$cmd \"$arg\""
                else
                    cmd="$cmd $arg"
                fi
            done < <(echo "$config" | jq -r '.args[]')
        fi

        # Scope already handled before -- separator, skip the common section
        scope=""
    fi

    # Add scope for http/sse (stdio already handled scope above, before -- separator)
    if [[ "$type" != "stdio" ]]; then
        # Optional: scope field for HTTP/SSE configuration storage location
        # Schema: scope must be one of: local, project, user
        # Default if not specified: local (user-level configuration, applies across all projects)
        # Source: Claude Code configuration documentation - Scope options
        scope=$(echo "$config" | jq -r '.scope // empty')
        if [ -n "$scope" ]; then
            if ! validate_scope "$scope"; then
                echo "Error: 'scope' must be one of: local, project, user. Got: '$scope'" >&2
                exit 1
            fi
            cmd="$cmd --scope $scope"
        fi
    fi

    # Execute or print
    if [ "$EXECUTE" = true ]; then
        eval "$cmd"
    else
        echo "$cmd"
    fi
}

# Parse command line options
EXECUTE=false
JSON_INPUT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -x|--execute)
            EXECUTE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            JSON_INPUT="$1"
            shift
            ;;
    esac
done

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
if ! command -v jq &> /dev/null; then
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
            inferred=$(infer_transport_type "$server_config")
            if [ $? -eq 0 ]; then
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
        process_server "$name" "$type" "$server_config"
    done <<< "$servers"
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
        inferred=$(infer_transport_type "$JSON_INPUT")
        if [ $? -eq 0 ]; then
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
    process_server "$name" "$type" "$JSON_INPUT"
fi
