# Magi Archive MCP Server

## Overview

The Magi Archive MCP (Model Context Protocol) Server enables seamless integration with Claude Desktop, Codex, and other MCP-compatible clients. This allows AI assistants to directly interact with the Magi Archive wiki through a standardized protocol.

**Status:** ✅ Implemented and ready for use

## What is MCP?

The [Model Context Protocol](https://modelcontextprotocol.io) is an open standard created by Anthropic for connecting AI assistants to external data sources and tools. It uses JSON-RPC 2.0 over stdio for communication.

## Features

### Available Tools

The MCP server exposes these tools to Claude Desktop and other clients:

1. **get_card** - Fetch a single card by name
2. **search_cards** - Search for cards by query, type, or filters
3. **create_card** - Create new cards on the wiki
4. **create_weekly_summary** - Generate automated weekly summaries

### Planned Tools

Future versions will add:
- update_card - Modify existing cards
- delete_card - Remove cards (admin only)
- list_children - Get child cards
- validate_tags - Validate card tags
- recommend_structure - Get card structure recommendations

## Installation

### Prerequisites

- Ruby 3.2 or higher
- Bundler
- Claude Desktop or Codex installed

### Option 1: Ruby Installation (Recommended)

```bash
# Clone the repository
git clone https://github.com/your-org/magi-archive-mcp.git
cd magi-archive-mcp

# Install dependencies
bundle install

# Install for Claude Desktop
ruby bin/install-claude-desktop

# OR install for Codex
ruby bin/install-codex
```

The installer will:
1. Prompt for authentication credentials
2. Configure your working directory
3. Update the appropriate config file
4. Make the server executable

### Option 2: NPM Installation

```bash
# Install via npm
npm install -g magi-archive-mcp

# Install for Claude Desktop
magi-archive-install-claude

# OR install for Codex
magi-archive-install-codex
```

### Manual Installation

If you prefer to configure manually:

#### Claude Desktop (macOS)

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "magi-archive": {
      "command": "ruby",
      "args": [
        "/path/to/magi-archive-mcp/bin/mcp-server",
        "/path/to/your/working/directory"
      ],
      "env": {
        "MCP_USERNAME": "your-username",
        "MCP_PASSWORD": "your-password",
        "DECKO_API_BASE_URL": "https://wiki.magi-agi.org/api/mcp"
      }
    }
  }
}
```

#### Claude Desktop (Windows)

Edit `%APPDATA%\Claude\claude_desktop_config.json` with the same structure.

#### Codex

Edit `~/.config/codex/mcp_config.json` (or equivalent on Windows) with the same structure.

## Authentication

The MCP server supports two authentication methods:

### Method 1: Username/Password (Recommended)

```json
{
  "env": {
    "MCP_USERNAME": "your-decko-username",
    "MCP_PASSWORD": "your-decko-password"
  }
}
```

### Method 2: API Key

```json
{
  "env": {
    "MCP_API_KEY": "your-64-char-api-key",
    "MCP_ROLE": "user"
  }
}
```

Contact your Decko administrator to get an API key.

## Usage

### With Claude Desktop

After installation and restarting Claude Desktop:

```
You: Get the Main Page card from Magi Archive

Claude: I'll fetch the Main Page card for you.
[Uses get_card tool]

Here's the Main Page:
Name: Main Page
Type: Basic
...
```

### With Codex

```bash
codex "Search for cards about Butterfly Galaxii in Magi Archive"
```

### Available Commands

#### Get a Card

```
"Get the card named 'Business Plan+Executive Summary' from Magi Archive"
"Fetch the Home card with its children"
```

#### Search Cards

```
"Search Magi Archive for cards about species"
"Find all Article type cards in Magi Archive"
"Search for cards updated in the last week"
```

#### Create Cards

```
"Create a new card called 'My New Article' in Magi Archive"
"Add a card with type RichText and this content: ..."
```

#### Weekly Summaries

```
"Generate a weekly summary for Magi Archive"
"Create a weekly summary for the last 14 days"
"Preview a weekly summary without creating the card"
```

## Working Directory

The MCP server scans git repositories in your working directory for the weekly summary feature. You can specify this during installation or in the config:

```json
{
  "args": [
    "/path/to/mcp-server",
    "/path/to/your/projects"  ← Working directory
  ]
}
```

This directory is used for:
- Scanning git repositories for commits
- Generating weekly summaries with repository activity

## Troubleshooting

### Server Won't Start

**Check Ruby version:**
```bash
ruby --version
# Should be 3.2 or higher
```

**Check dependencies:**
```bash
cd magi-archive-mcp
bundle install
```

**Check authentication:**
Ensure your `.env` file or config has valid credentials.

### Tools Not Appearing in Claude Desktop

1. **Restart Claude Desktop** completely
2. **Check config file** syntax (must be valid JSON)
3. **Check server logs** in Claude Desktop developer tools
4. **Verify file paths** are absolute, not relative

### Permission Denied Errors

```bash
chmod +x bin/mcp-server
chmod +x bin/install-claude-desktop
chmod +x bin/install-codex
```

### Authentication Failures

- Verify credentials are correct
- Check that the Decko API is accessible
- Ensure DECKO_API_BASE_URL is correct
- Try authenticating with the client library directly:

```ruby
require './lib/magi/archive/mcp'
tools = Magi::Archive::Mcp::Tools.new
puts tools.get_card('Home')
```

## Development

### Adding New Tools

1. Create a new tool class in `lib/magi/archive/mcp/server/tools/`:

```ruby
require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          class MyNewTool < ::MCP::Tool
            description "Description of what this tool does"

            input_schema(
              properties: {
                param1: {
                  type: "string",
                  description: "Description of param1"
                }
              },
              required: ["param1"]
            )

            class << self
              def call(param1:, server_context:)
                tools = server_context[:magi_tools]

                # Your tool logic here
                result = tools.some_method(param1)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_result(result)
                }])
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: #{e.message}"
                }], is_error: true)
              end

              private

              def format_result(result)
                # Format the result for display
              end
            end
          end
        end
      end
    end
  end
end
```

2. Register it in `bin/mcp-server`:

```ruby
require_relative "../lib/magi/archive/mcp/server/tools/my_new_tool"

server = ::MCP::Server.new(
  # ...
  tools: [
    # ... existing tools ...
    Magi::Archive::Mcp::Server::Tools::MyNewTool
  ]
)
```

### Testing the Server

```bash
# Run the server directly
ruby bin/mcp-server /path/to/working/dir

# Send test JSON-RPC request
echo '{"jsonrpc":"2.0","id":"1","method":"tools/list"}' | ruby bin/mcp-server
```

Expected response:
```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "result": {
    "tools": [
      {
        "name": "get_card",
        "description": "Get a single card by name from the Magi Archive wiki",
        "inputSchema": { ... }
      },
      ...
    ]
  }
}
```

## Architecture

### Components

```
┌─────────────────────┐
│  Claude Desktop /   │
│      Codex          │
└──────────┬──────────┘
           │ JSON-RPC over stdio
           ▼
┌─────────────────────┐
│   MCP Server        │
│  (bin/mcp-server)   │
└──────────┬──────────┘
           │ Ruby API calls
           ▼
┌─────────────────────┐
│   Magi::Archive::   │
│   Mcp::Tools        │
└──────────┬──────────┘
           │ HTTP/JWT
           ▼
┌─────────────────────┐
│  Decko API Server   │
│  (wiki.magi-agi.org)│
└─────────────────────┘
```

### Communication Flow

1. **User types request** in Claude Desktop
2. **Claude decides to use** Magi Archive tool
3. **Claude sends JSON-RPC** request to MCP server via stdio
4. **MCP server** deserializes request, calls appropriate tool class
5. **Tool class** uses `Magi::Archive::Mcp::Tools` to interact with API
6. **Tools class** authenticates and makes HTTP request to Decko
7. **Decko API** returns JSON response
8. **Tool class** formats response for display
9. **MCP server** sends JSON-RPC response back to Claude
10. **Claude displays** result to user

## Security

### Credentials Storage

- Credentials are stored in Claude Desktop/Codex config files
- These files are user-specific and not shared
- Never commit config files to version control
- Use environment variables for CI/CD

### Authentication

- All API requests use JWT authentication
- Tokens are short-lived (15-60 minutes)
- Role-based access control (user/gm/admin)
- Automatic token refresh

### Network Security

- All communication with Decko over HTTPS
- stdio communication is local (not network)
- No credentials sent to MCP clients

## Performance

### Response Times

- Card fetch: ~100-500ms
- Search: ~200-800ms (depends on result size)
- Weekly summary: ~2-5s (scans git repos)

### Rate Limiting

The Decko API enforces rate limits:
- Default: 50 requests per minute per API key
- Automatic retry with exponential backoff

### Caching

- No client-side caching currently
- Server-side tag caching (5 minutes)
- Consider adding tool result caching for repeated queries

## Changelog

### Version 1.0.0 (2025-12-03)

**Initial MCP Server Implementation**

Features:
- ✅ get_card tool with full card data
- ✅ search_cards with pagination
- ✅ create_card for new content
- ✅ create_weekly_summary with git integration
- ✅ Auto-installers for Claude Desktop and Codex
- ✅ NPM wrapper for Node.js users
- ✅ Comprehensive documentation

Protocol:
- ✅ JSON-RPC 2.0 over stdio
- ✅ MCP specification 2025-03-26 compliant
- ✅ Tool schema validation
- ✅ Error handling and formatting

Authentication:
- ✅ Username/password support
- ✅ API key support
- ✅ Automatic token refresh
- ✅ Role-based access

## Resources

- **MCP Specification:** https://spec.modelcontextprotocol.io
- **MCP Ruby SDK:** https://github.com/modelcontextprotocol/ruby-sdk
- **Magi Archive Wiki:** https://wiki.magi-agi.org
- **Issue Tracker:** https://github.com/your-org/magi-archive-mcp/issues

## Contributing

Contributions are welcome! To add new tools:

1. Create tool class following the pattern
2. Add comprehensive documentation
3. Write tests for the tool
4. Update this documentation
5. Submit a pull request

## License

MIT License - See LICENSE file for details

## Support

For issues, questions, or feature requests:
- GitHub Issues: https://github.com/your-org/magi-archive-mcp/issues
- Wiki: https://wiki.magi-agi.org
- Email: support@magi-agi.org
