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

## Transport Type Inference

The `type` field is **optional** and will be automatically inferred from the configuration structure if not provided. This makes configurations simpler and less verbose.

### Inference Rules

The transport type is determined by the presence of specific fields:

- **If `command` is present and `url` is absent** → `stdio` transport
- **If `url` is present and `command` is absent** → `http` transport
- **If both `command` and `url` are present, or neither is present** → `type` field is required

### Examples

```bash
# Inferred as stdio (has command, no url)
./json-to-mcp-add.sh '{"name":"my-server","command":"npx","args":["mcp-server"]}'

# Inferred as http (has url, no command)
./json-to-mcp-add.sh '{"name":"api-server","url":"https://api.example.com"}'

# Explicit type overrides inference (has both, but type is specified)
./json-to-mcp-add.sh '{"name":"mixed","type":"http","command":"echo","url":"https://example.com"}'

# Requires explicit type (ambiguous: has both command and url)
./json-to-mcp-add.sh '{"name":"ambiguous","command":"cmd","url":"https://example.com"}'
# Error: 'type' field is required. Provide 'type' explicitly...
```

## JSON Configuration Formats

### Format 1: Flat Format

```json
{
  "name": "server-name",              // (required) Unique server identifier
  "type": "http|sse|stdio",           // (optional) Transport type — inferred if omitted
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
      "type": "http|sse|stdio",       // (optional) Transport type — inferred if omitted
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

#### HTTP Server (Type Inferred)

Since the configuration has `url` and no `command`, the type is automatically inferred as `http`:

```bash
./json-to-mcp-add.sh << 'EOF'
{
  "name": "github",
  "url": "https://mcp.github.com/api",
  "headers": {
    "Authorization": "Bearer ghp_..."
  }
}
EOF
```

Output:
```
claude mcp add --transport http github https://mcp.github.com/api --header "Authorization: Bearer ghp_..."
```

#### Stdio Server (Type Inferred)

Since the configuration has `command` and no `url`, the type is automatically inferred as `stdio`:

```bash
./json-to-mcp-add.sh << 'EOF'
{
  "name": "local-server",
  "command": "node",
  "args": ["server.js"],
  "env": {
    "PORT": "3000"
  }
}
EOF
```

Output:
```
claude mcp add --transport stdio local-server --env PORT="3000" -- node server.js
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

The script validates all input against the official MCP server configuration schema as defined in the MCP specification and Claude Code documentation.

**Schema Sources:**
- [MCP Specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)
- Claude Code Configuration Documentation
- POSIX Shell Specification (for environment variable naming)

### Type Validation

- `type` must be one of: `http`, `sse`, `stdio`
  - `http`: Remote HTTP/HTTPS endpoint (recommended)
  - `sse`: Remote Server-Sent Events endpoint (deprecated, use http)
  - `stdio`: Local process via standard input/output
- `http`/`sse` require `url` field
- `stdio` requires `command` field

### Field Type Validation

- `headers` must be an object (key-value pairs) — used for HTTP/SSE authentication
- `env` must be an object with valid environment variable names — used for stdio environment
- `args` must be an array of strings — used for stdio command arguments

### Format Validation

- **Server names**: Alphanumeric characters, hyphens, and underscores only
  - Pattern: `[a-zA-Z0-9_-]+`
  - Used as configuration object keys
- **URLs**: Must be valid HTTP(S) URLs with protocol
  - Pattern: `https?://[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}(/.*)?`
  - Required for http and sse transports
- **Scope**: One of `local`, `project`, `user`
  - `local`: Project-level configuration (~/.claude.json)
  - `project`: Repository configuration (.mcp.json, shared with team)
  - `user`: Global user configuration (cross-project)
- **Environment variable names**: POSIX shell variable naming convention
  - Pattern: `[a-zA-Z_][a-zA-Z0-9_]*`
  - Must start with letter or underscore
  - Can contain letters, digits, and underscores

### Validation Rules

- All required fields must be present
- Type-specific required fields are validated (url for http/sse, command for stdio)
- Field types are strictly validated (objects must be objects, arrays must be arrays)
- No extra fields are rejected — the script only uses defined schema fields
- Invalid JSON input is rejected with clear error messages

### Error Handling

The script validates all inputs and provides clear, actionable error messages:

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

## Design Principles

This script implements comprehensive schema validation based on the official MCP specification:

1. **Schema-Driven** — All validation rules are derived from the MCP specification and Claude Code documentation
2. **Strict Validation** — Fields are validated for type, format, and content according to schema rules
3. **Transparent Conversion** — The script converts between two supported JSON formats (flat and Claude Desktop)
4. **Clear Errors** — Validation failures include specific, actionable error messages citing the schema rule violated
5. **No Data Loss** — All schema-valid configuration is preserved in the generated command

## Implementation Details

The validation functions in the script are documented with:
- The specific MCP schema rule being validated
- The source of the rule (specification version, documentation link)
- The pattern or constraint being enforced
- The purpose of the validation

To understand the schema validation details, see comments in `json-to-mcp-add.sh` which cite:
- MCP Specification 2025-11-25
- Claude Code Configuration Documentation
- POSIX Shell Variable Naming Convention

## Requirements

- Bash (4.0+)
- `jq` (1.6+) for JSON parsing and validation

## Help

```bash
./json-to-mcp-add.sh -h
./json-to-mcp-add.sh --help
```

## Contributing

When making changes:
1. Ensure all validation rules match the MCP specification
2. Add comments documenting schema rules and sources
3. Update README if changing validation behaviour
4. Test with both flat and Claude Desktop JSON formats

## References

- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [Claude Code Documentation](https://code.claude.com/docs)
- [POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)
- [JSON (RFC 8259)](https://tools.ietf.org/html/rfc8259)

## License

MIT
