# mcp-commandline

A shell script that converts JSON MCP server configuration into `claude mcp add` command-line calls.

## Overview

This script simplifies adding Model Context Protocol (MCP) servers to Claude Code by accepting JSON configuration and generating the appropriate `claude mcp add` command. It handles all three transport types: HTTP, SSE, and stdio.

## Installation

```bash
git clone https://github.com/jamiemills/mcp-commandline.git
cd mcp-commandline
chmod +x json-to-mcp-add.sh
```

## Usage

The script accepts JSON input via stdin or as a command argument.

### Basic Usage

```bash
# Via stdin
echo '{"name":"myserver","type":"http","url":"https://api.example.com"}' | ./json-to-mcp-add.sh

# Via argument
./json-to-mcp-add.sh '{"name":"myserver","type":"http","url":"https://api.example.com"}'

# From file
./json-to-mcp-add.sh < config.json
```

### Execute the Command

By default, the script prints the generated command. Use `-x` or `--execute` to run it directly:

```bash
./json-to-mcp-add.sh -x < config.json
```

## JSON Configuration Formats

### Format 1: Flat Format

```json
{
  "name": "server-name",              // (required) Unique server identifier
  "type": "http|sse|stdio",           // (required) Transport type
  "url": "https://...",               // (required for http/sse)
  "command": "/path/to/cmd",          // (required for stdio)
  "args": ["arg1", "arg2"],           // (optional for stdio) Command arguments
  "headers": {                        // (optional for http/sse) Auth headers
    "Authorization": "Bearer token",
    "X-Custom-Header": "value"
  },
  "env": {                            // (optional for stdio) Environment variables
    "API_KEY": "secret",
    "CACHE_DIR": "/tmp/cache"
  },
  "scope": "local|project|user"       // (optional) Config scope (default: local)
}
```

### Format 2: Claude Desktop Config

This format matches the `mcpServers` object from Claude Desktop's configuration:

```json
{
  "mcpServers": {
    "server-name": {
      "type": "http|sse|stdio",       // (required) Transport type
      "url": "https://...",           // (required for http/sse)
      "command": "/path/to/cmd",      // (required for stdio)
      "args": ["arg1", "arg2"],       // (optional for stdio)
      "headers": {                    // (optional for http/sse)
        "Authorization": "Bearer token"
      },
      "env": {                        // (optional for stdio)
        "API_KEY": "secret"
      }
    }
  }
}
```

The script automatically detects which format is being used and handles both transparently.

### Scope Options

- `local` – Store in project-level `~/.claude.json` (default)
- `project` – Store in repository `.mcp.json` (shared with team)
- `user` – Store in global user configuration (cross-project)

## Examples

### Claude Desktop Config Format

Extract servers from a Claude Desktop config file:

```bash
./json-to-mcp-add.sh < ~/.claude/config.json
```

Output:
```
claude mcp add --transport http notion https://mcp.notion.com/mcp --header "Authorization: Bearer token"
claude mcp add --transport stdio airtable -- npx -y airtable-mcp-server
```

### Flat Format

#### HTTP Server with Authentication

```bash
./json-to-mcp-add.sh << 'EOF'
{
  "name": "notion",
  "type": "http",
  "url": "https://mcp.notion.com/mcp",
  "headers": {
    "Authorization": "Bearer sk_live_..."
  },
  "scope": "project"
}
EOF
```

Output:
```
claude mcp add --transport http notion https://mcp.notion.com/mcp --header "Authorization: Bearer sk_live_..." --scope project
```

#### Stdio Server with Environment Variables

```bash
./json-to-mcp-add.sh << 'EOF'
{
  "name": "airtable",
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "airtable-mcp-server"],
  "env": {
    "AIRTABLE_API_KEY": "pat_..."
  }
}
EOF
```

Output:
```
claude mcp add --transport stdio airtable --env AIRTABLE_API_KEY="pat_..." -- npx -y airtable-mcp-server
```

#### SSE Server

```bash
./json-to-mcp-add.sh '{"name":"asana","type":"sse","url":"https://mcp.asana.com/sse"}'
```

Output:
```
claude mcp add --transport sse asana https://mcp.asana.com/sse
```

## Schema Validation

The script validates all input against the MCP server configuration schema:

**Type Validation:**
- `type` must be one of: `http`, `sse`, `stdio`
- `http`/`sse` require `url` field
- `stdio` requires `command` field

**Format Validation:**
- Server names must contain only alphanumeric characters, hyphens, and underscores
- URLs must be valid HTTP(S) URLs with protocol
- `scope` values must be one of: `local`, `project`, `user`
- `headers` must be an object (key-value pairs)
- `env` must be an object with valid environment variable names
- `args` must be an array of strings
- Environment variable names must start with letter or underscore, contain only alphanumeric characters and underscores

**Error Handling:**

The script validates all inputs and provides clear error messages:

```bash
$ ./json-to-mcp-add.sh '{"name":"test"}'
Error: 'type' field is required

$ ./json-to-mcp-add.sh '{"name":"test","type":"http"}'
Error: 'url' field is required for http transport

$ ./json-to-mcp-add.sh '{"name":"test","type":"http","url":"invalid-url"}'
Error: Invalid URL format for 'invalid-url'. Must be valid HTTP(S) URL

$ ./json-to-mcp-add.sh '{"name":"invalid.name","type":"http","url":"https://api.example.com"}'
Error: Server name 'invalid.name' is invalid. Must contain only alphanumeric characters, hyphens, and underscores

$ ./json-to-mcp-add.sh '{"name":"test","type":"http","url":"https://api.example.com","scope":"invalid"}'
Error: 'scope' must be one of: local, project, user. Got: 'invalid'

$ echo '{"name":"test","type":"stdio","command":"npx","env":{"2INVALID":"val"}}' | ./json-to-mcp-add.sh
Error: Invalid environment variable name '2INVALID'. Must start with letter or underscore, contain only alphanumeric characters and underscores
```

## Requirements

- Bash
- `jq` (for JSON parsing)

## Help

```bash
./json-to-mcp-add.sh -h
./json-to-mcp-add.sh --help
```

## License

MIT
