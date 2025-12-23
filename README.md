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

## JSON Configuration Schema

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

### Scope Options

- `local` – Store in project-level `~/.claude.json` (default)
- `project` – Store in repository `.mcp.json` (shared with team)
- `user` – Store in global user configuration (cross-project)

## Examples

### HTTP Server with Authentication

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

### Stdio Server with Environment Variables

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

### SSE Server

```bash
./json-to-mcp-add.sh '{"name":"asana","type":"sse","url":"https://mcp.asana.com/sse"}'
```

Output:
```
claude mcp add --transport sse asana https://mcp.asana.com/sse
```

## Error Handling

The script validates all inputs and provides clear error messages:

```bash
$ ./json-to-mcp-add.sh '{"name":"test"}'
Error: 'type' field is required

$ ./json-to-mcp-add.sh '{"name":"test","type":"http"}'
Error: 'url' field is required for http transport
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
