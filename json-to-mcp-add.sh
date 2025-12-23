#!/bin/bash

set -euo pipefail

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [JSON_INPUT]

Convert JSON MCP server configuration to 'claude mcp add' command.

Input can be provided as:
  - First argument: $0 '{"name":"server","type":"http",...}'
  - stdin: echo '{"name":"server",...}' | $0

Options:
  -x, --execute    Execute the command instead of printing it
  -h, --help       Show this help message

JSON Schema:
  {
    "name": "server-name",           (required)
    "type": "http|sse|stdio",        (required)
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
EOF
    exit 1
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

# Validate jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Extract and validate required fields
name=$(echo "$JSON_INPUT" | jq -r '.name // empty')
type=$(echo "$JSON_INPUT" | jq -r '.type // empty')

if [ -z "$name" ]; then
    echo "Error: 'name' field is required" >&2
    exit 1
fi

if [ -z "$type" ]; then
    echo "Error: 'type' field is required" >&2
    exit 1
fi

# Validate type
if [[ ! "$type" =~ ^(http|sse|stdio)$ ]]; then
    echo "Error: 'type' must be one of: http, sse, stdio" >&2
    exit 1
fi

# Build base command
cmd="claude mcp add --transport $type $name"

# Build command based on transport type
if [[ "$type" == "http" ]] || [[ "$type" == "sse" ]]; then
    # HTTP/SSE: require url
    url=$(echo "$JSON_INPUT" | jq -r '.url // empty')

    if [ -z "$url" ]; then
        echo "Error: 'url' field is required for $type transport" >&2
        exit 1
    fi

    cmd="$cmd $url"

    # Add headers if present
    headers=$(echo "$JSON_INPUT" | jq -r '.headers // empty')
    if [ -n "$headers" ] && [ "$headers" != "null" ]; then
        while IFS= read -r line; do
            key=$(echo "$line" | jq -r '.key')
            value=$(echo "$line" | jq -r '.value')
            cmd="$cmd --header \"$key: $value\""
        done < <(echo "$JSON_INPUT" | jq -c '.headers | to_entries[] | {key: .key, value: .value}')
    fi

elif [[ "$type" == "stdio" ]]; then
    # Stdio: require command
    command=$(echo "$JSON_INPUT" | jq -r '.command // empty')

    if [ -z "$command" ]; then
        echo "Error: 'command' field is required for stdio transport" >&2
        exit 1
    fi

    # Add environment variables if present
    env_vars=$(echo "$JSON_INPUT" | jq -r '.env // empty')
    if [ -n "$env_vars" ] && [ "$env_vars" != "null" ]; then
        while IFS= read -r line; do
            key=$(echo "$line" | jq -r '.key')
            value=$(echo "$line" | jq -r '.value')
            cmd="$cmd --env $key=\"$value\""
        done < <(echo "$JSON_INPUT" | jq -c '.env | to_entries[] | {key: .key, value: .value}')
    fi

    # Add scope before the -- separator if present
    scope=$(echo "$JSON_INPUT" | jq -r '.scope // empty')
    if [ -n "$scope" ]; then
        cmd="$cmd --scope $scope"
    fi

    # Add mandatory -- separator
    cmd="$cmd --"

    # Add command
    cmd="$cmd $command"

    # Add args if present
    args=$(echo "$JSON_INPUT" | jq -r '.args // empty')
    if [ -n "$args" ] && [ "$args" != "null" ]; then
        while IFS= read -r arg; do
            # Quote args that contain spaces
            if [[ "$arg" =~ [[:space:]] ]]; then
                cmd="$cmd \"$arg\""
            else
                cmd="$cmd $arg"
            fi
        done < <(echo "$JSON_INPUT" | jq -r '.args[]')
    fi

    # Scope already handled before -- separator, skip the common section
    scope=""
fi

# Add scope for http/sse (stdio handled separately above)
if [[ "$type" != "stdio" ]]; then
    scope=$(echo "$JSON_INPUT" | jq -r '.scope // empty')
    if [ -n "$scope" ]; then
        cmd="$cmd --scope $scope"
    fi
fi

# Execute or print
if [ "$EXECUTE" = true ]; then
    eval "$cmd"
else
    echo "$cmd"
fi
