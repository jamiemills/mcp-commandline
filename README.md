# mcp-commandline

A shell script that converts JSON MCP server configuration into MCP CLI commands for Claude Code or Sourcegraph Amp.

**Status:** ✅ Production Ready — 45+ tests passing (100% success rate)

## Overview

This script simplifies adding Model Context Protocol (MCP) servers to your preferred CLI tool by accepting JSON configuration and generating the appropriate MCP command. It handles all three transport types: HTTP, SSE, and stdio. Supports both Claude Code (`claude mcp add`) and Sourcegraph Amp (`amp mcp add`).

The tool features:
- **Full CLI Support** — Generates commands for both Claude Code and Sourcegraph Amp with correct syntax differences
- **Automatic Transport Inference** — Detects `http`, `sse`, or `stdio` from your configuration
- **Complete Validation** — RFC 3986 URL validation, POSIX environment variable names, field type checking
- **Header Format Translation** — Automatically converts headers to CLI-specific format (colon-space for Claude, equals for Amp)
- **Scope Management** — Handles CLI-specific scope options for configuration storage
- **Preference Persistence** — Saves your CLI choice for subsequent uses

## Specification Compliance

This script generates MCP server configuration commands that conform to official specifications for multiple CLIs. Each CLI has specific requirements and supported features.

### Claude Code Specification
- **Source**: [Claude Code Documentation](https://code.claude.com/docs/en/mcp)
- **Version**: Latest (updated Jan 2025)
- **Transport Detection**: Explicit via `--transport` flag
- **Supported Transports**: http, sse, stdio
- **Scope Support**: Yes (local, project, user)
- **Header Format**: `"Key: Value"` (colon with space)

### Amp Specification
- **Source**: [Amp Manual - MCP](https://ampcode.com/manual)
- **Version**: Latest (updated Jan 2025)
- **Transport Detection**: Automatic from server headers (no flag)
- **Supported Transports**: http, sse, stdio
- **Scope Support**: No (uses global amp.mcpServers)
- **Header Format**: `"Key=Value"` (equals, no space)
- **Additional Features**: includeTools for tool filtering (stdio only)

### General MCP Standard
- **Specification**: [Model Context Protocol](https://modelcontextprotocol.io/)
- **Version**: 2025-11-25

## Feature Comparison: Claude Code vs. Amp

| Feature | Claude Code | Amp | Notes |
|---------|-------------|-----|-------|
| **Transport: HTTP** | ✅ Yes | ✅ Yes | Default for URL-based servers |
| **Transport: SSE** | ✅ Yes | ✅ Yes | Deprecated, use HTTP |
| **Transport: Stdio** | ✅ Yes | ✅ Yes | For local processes |
| **Transport Flag** | ✅ Required | ❌ Auto-detect | Claude requires explicit flag |
| **Scope Support** | ✅ Yes | ❌ No | Amp uses global location only |
| **Scope Options** | local, project, user | N/A | Control where config is stored |
| **Header Format** | `"Key: Value"` | `"Key=Value"` | Different separator syntax |
| **includeTools** | ❌ Not supported | ✅ Yes (stdio) | Filters which tools are exposed |
| **Command Prefix** | `claude mcp add` | `amp mcp add` | Different CLI commands |

### Key Differences Summary

1. **Headers**: Claude uses colon format (`Authorization: token`), Amp uses equals format (`Authorization=token`)
2. **Scope**: Claude supports it, Amp doesn't (global only)
3. **Transport Flag**: Claude requires it, Amp auto-detects
4. **includeTools**: Amp-specific for tool filtering

## Installation

```bash
git clone https://github.com/jamiemills/mcp-commandline.git
cd mcp-commandline
chmod +x json-to-mcp-add.sh
```

## Usage

The script accepts JSON input via stdin or as a command argument.

### CLI Selection

Use the `--cli` option to specify your target platform:

```bash
# Generate Claude Code command (default if not specified or saved)
json-to-mcp-add.sh --cli claude '{"name":"myserver","url":"https://api.example.com"}'
# Output: claude mcp add --transport http myserver https://api.example.com

# Generate Sourcegraph Amp command
json-to-mcp-add.sh --cli amp '{"name":"myserver","url":"https://api.example.com"}'
# Output: amp mcp add myserver https://api.example.com
```

**Preference Persistence:** Your CLI choice is automatically saved to `~/.config/mcp-commandline/config` (or `~/.mcp-commandline-config` as fallback). Once you specify a CLI preference, you don't need to include `--cli` on subsequent invocations—it will use your saved preference.

```bash
# First use - save preference
json-to-mcp-add.sh --cli amp '{"name":"server","url":"https://..."}'

# Subsequent uses - uses saved preference (amp)
json-to-mcp-add.sh '{"name":"server2","url":"https://..."}'

# Override saved preference
json-to-mcp-add.sh --cli claude '{"name":"server3","url":"https://..."}'
```

### Basic Usage

```bash
# Via stdin
echo '{"name":"myserver","type":"http","url":"https://api.example.com"}' | json-to-mcp-add.sh

# Via argument
json-to-mcp-add.sh '{"name":"myserver","type":"http","url":"https://api.example.com"}'

# From file
json-to-mcp-add.sh < config.json
```

### Execute the Command

By default, the script prints the generated command. Use `-x` or `--execute` to run it directly:

```bash
json-to-mcp-add.sh -x < config.json
json-to-mcp-add.sh --cli amp -x < config.json
```

## Understanding MCP Communication Layers

When you configure an MCP server with this script, you're participating in a layered communication system. Understanding these layers helps you know what this tool does and what happens after:

### Layer 1: Transport Layer (This Script's Responsibility)
**Where and how to connect** — The script validates your configuration and generates the appropriate MCP command (`claude mcp add` or `amp mcp add`) that tells your CLI tool:
- Which protocol to use (stdio, HTTP, or SSE)
- Where the server is located (command path or URL)
- How to authenticate (headers for HTTP/SSE, environment variables for stdio)

### Layer 2: Connection Layer (CLI Runtime)
**Establishing the connection** — The CLI runtime (Claude Code or Amp) handles:
- TCP/TLS socket creation
- Process spawning (for stdio)
- HTTP/HTTPS connections (for remote servers)

### Layer 3: Protocol Layer (CLI Runtime)
**Speaking MCP** — Once connected, the CLI runtime performs:
- JSON-RPC 2.0 message exchange
- `InitializeRequest` handshake to negotiate capabilities
- `InitializeResponse` containing what the server offers

### Layer 4: Feature Layer (The MCP Server)
**What the server actually does** — After initialization, the server provides:
- **Resources** — Data sources and context documents
- **Tools** — Functions that Claude can call
- **Prompts** — Reusable message templates
- **Sampling** — Server-initiated LLM requests (advanced)

**Example Flow:**
```
Script: "Connect to https://api.example.com using HTTP"
  ↓
Runtime: Establishes HTTPS connection
  ↓
Runtime: Sends: {"jsonrpc": "2.0", "method": "initialize", ...}
  ↓
Server: Responds: {"result": {"capabilities": {"resources": {}, "tools": {}}}}
  ↓
Claude: Now has access to the server's resources and tools
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
json-to-mcp-add.sh '{"name":"my-server","command":"npx","args":["mcp-server"]}'

# Inferred as http (has url, no command)
json-to-mcp-add.sh '{"name":"api-server","url":"https://api.example.com"}'

# Explicit type overrides inference (has both, but type is specified)
json-to-mcp-add.sh '{"name":"mixed","type":"http","command":"echo","url":"https://example.com"}'

# Requires explicit type (ambiguous: has both command and url)
json-to-mcp-add.sh '{"name":"ambiguous","command":"cmd","url":"https://example.com"}'
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

- `local` – User-level configuration stored in `~/.claude.json` (default) — applies across all projects for the current user
- `project` – Repository-level configuration stored in `.mcp.json` at repository root (shared with team)
- `user` – Global user configuration (same as `local`, for compatibility)

## Examples

### Claude Desktop Config Format

Extract servers from a Claude Desktop config file for Claude Code:

```bash
json-to-mcp-add.sh --cli claude < ~/.claude/config.json
```

Output:
```
claude mcp add --transport http notion https://mcp.notion.com/mcp --header "Authorization: Bearer token"
claude mcp add --transport stdio airtable -- npx -y airtable-mcp-server
```

Or for Sourcegraph Amp:

```bash
json-to-mcp-add.sh --cli amp < ~/.claude/config.json
```

Output:
```
amp mcp add notion https://mcp.notion.com/mcp --header "Authorization=Bearer token"
amp mcp add airtable stdio npx -y airtable-mcp-server
```

Note the differences:
- Amp omits `--transport` flag (auto-detected)
- Amp uses `=` in headers instead of `: `
- Amp omits `--` separator for stdio

### Flat Format

#### HTTP Server with Authentication (Claude Code)

```bash
json-to-mcp-add.sh --cli claude << 'EOF'
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

#### HTTP Server with Authentication (Sourcegraph Amp)

```bash
json-to-mcp-add.sh --cli amp << 'EOF'
{
  "name": "notion",
  "type": "http",
  "url": "https://mcp.notion.com/mcp",
  "headers": {
    "Authorization": "Bearer sk_live_..."
  }
}
EOF
```

Output:
```
amp mcp add --transport http notion https://mcp.notion.com/mcp --header "Authorization: Bearer sk_live_..."
```

#### Stdio Server with Environment Variables

```bash
json-to-mcp-add.sh --cli claude << 'EOF'
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

Or for Amp:

```bash
json-to-mcp-add.sh --cli amp << 'EOF'
{
  "name": "postgres",
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-postgres"],
  "env": {
    "PGUSER": "admin"
  }
}
EOF
```

Output:
```
amp mcp add postgres stdio npx -y @modelcontextprotocol/server-postgres PGUSER="admin"
```

Note: Amp places environment variables after the command/args (no `--env` prefix, no `--` separator).

#### HTTP Server (Type Inferred)

Since the configuration has `url` and no `command`, the type is automatically inferred as `http`:

```bash
json-to-mcp-add.sh << 'EOF'
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
json-to-mcp-add.sh << 'EOF'
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
claude mcp add --transport stdio local-server -- node server.js PORT="3000"
```

Note: Environment variables are placed after the command and arguments.

#### SSE Server

```bash
json-to-mcp-add.sh '{"name":"asana","type":"sse","url":"https://mcp.asana.com/sse"}'
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
- **URLs**: Must be valid HTTP(S) URLs per RFC 3986 specification
  - Format: `http[s]://host[:port][/path][?query][#fragment]`
  - Host can be: domain name, IPv4 address, IPv6 address (in brackets), or localhost
  - Port is optional (decimal digits 1-5)
  - Path, query parameters, and fragments are optional
  - Domain labels must start and end with alphanumeric, can contain hyphens
  - Examples: `https://api.example.com:3000/path?key=value#section`, `https://192.168.1.1:8080`
  - Required for http and sse transports
- **Scope**: One of `local`, `project`, `user`
  - `local`: User-level configuration stored in `~/.claude.json` (default)
  - `project`: Repository-level configuration stored in `.mcp.json` at repository root (shared with team)
  - `user`: Alias for `local` (for compatibility)
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
$ json-to-mcp-add.sh '{"name":"test"}'
Error: 'type' field is required

$ json-to-mcp-add.sh '{"name":"test","type":"http"}'
Error: 'url' field is required for http transport

$ json-to-mcp-add.sh '{"name":"test","type":"http","url":"invalid-url"}'
Error: Invalid URL format for 'invalid-url'. Must be valid HTTP(S) URL

$ json-to-mcp-add.sh '{"name":"invalid.name","type":"http","url":"https://api.example.com"}'
Error: Server name 'invalid.name' is invalid. Must contain only alphanumeric characters, hyphens, and underscores

$ json-to-mcp-add.sh '{"name":"test","type":"http","url":"https://api.example.com","scope":"invalid"}'
Error: 'scope' must be one of: local, project, user. Got: 'invalid'

$ echo '{"name":"test","type":"stdio","command":"npx","env":{"2INVALID":"val"}}' | json-to-mcp-add.sh
Error: Invalid environment variable name '2INVALID'. Must start with letter or underscore, contain only alphanumeric characters and underscores
```

## What Happens After Configuration

Once you run the generated MCP command (for either Claude Code or Amp), the CLI performs the following sequence:

### 1. Configuration Storage
The server configuration is saved to the specified scope:
- `local` → `~/.claude.json` (user-level, default) — available across all projects
- `project` → `.mcp.json` (repository root) — team-shared configuration
- `user` → `~/.claude.json` (same as `local`, for compatibility)

### 2. Server Initialization
When the CLI starts or you interact with the server, it:
- Connects using the configured transport (stdio command, HTTP URL, or SSE endpoint)
- Sends an `InitializeRequest` containing:
  - Protocol version requirement
  - Implementation name and version
  - Requested capabilities (resources, tools, prompts, sampling, etc.)

### 3. Capability Negotiation
The server responds with `InitializeResponse` containing:
- Protocol version agreement
- **Available resources** — Data sources Claude can access
- **Available tools** — Functions Claude can invoke
- **Available prompts** — Message templates Claude can use
- **Server capabilities** — What advanced features the server supports

### 4. Runtime Operation
Once initialized, the CLI can:
- Request resources from the server for context
- Call tools provided by the server
- Use prompts to structure queries
- For advanced servers: allow server to initiate sampling requests

### Example: Configuring a GitHub MCP Server

```bash
# Configuration (what this script does)
json-to-mcp-add.sh << 'EOF'
{
  "name": "github",
  "url": "https://mcp.github.com",
  "headers": {"Authorization": "Bearer ghp_..."}
}
EOF

# Output: claude mcp add --transport http github https://mcp.github.com --header "Authorization: Bearer ghp_..."

# What happens after (what the CLI does)
# 1. Stores configuration in ~/.claude.json (user-level, available across projects)
# 2. On next use, connects to https://mcp.github.com
# 3. Sends InitializeRequest negotiating capabilities
# 4. Receives InitializeResponse with available resources/tools
# 5. You can now ask the CLI to search GitHub, create issues, etc.
```

## Design Principles

This script implements comprehensive schema validation based on the official MCP specification:

1. **Schema-Driven** — All validation rules are derived from the MCP specification and CLI documentation
2. **Strict Validation** — Fields are validated for type, format, and content according to schema rules
3. **Transparent Conversion** — The script converts between two supported JSON formats (flat and Claude Desktop)
4. **Clear Errors** — Validation failures include specific, actionable error messages citing the schema rule violated
5. **No Data Loss** — All schema-valid configuration is preserved in the generated command
6. **Layered Architecture** — Focuses solely on transport configuration, leaving protocol negotiation to the CLI runtime

## Implementation Details

The validation functions in the script are documented with:
- The specific MCP schema rule being validated
- The source of the rule (specification version, documentation link)
- The pattern or constraint being enforced
- The purpose of the validation

To understand the schema validation details, see comments in `json-to-mcp-add.sh` which cite:
- MCP Specification 2025-11-25
- CLI Configuration Documentation
- POSIX Shell Variable Naming Convention

## Requirements

- Bash (4.0+)
- `jq` (1.6+) for JSON parsing and validation

## Help

```bash
json-to-mcp-add.sh -h
json-to-mcp-add.sh --help
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
