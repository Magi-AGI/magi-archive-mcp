# Magi Archive MCP Client & Tools

A Ruby client library and MCP protocol server for the Magi Archive API (`wiki.magi-agi.org`). This package provides both a Ruby library for programmatic access and MCP protocol tools for integration with AI assistants like Claude Desktop, Claude Code, and Codex.

[![npm](https://img.shields.io/npm/v/@magi-agi/mcp-server)](https://www.npmjs.com/package/@magi-agi/mcp-server)
[![Ruby](https://img.shields.io/badge/Ruby-3.2%2B-red)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-102%20passing-brightgreen)](spec/)
[![RuboCop](https://img.shields.io/badge/code%20style-rubocop-brightgreen.svg)](https://rubocop.org/)
[![Phase](https://img.shields.io/badge/implementation-Phase%202-blue)]()

## Overview

This package has two main components:

1. **Ruby Client Library** (`lib/magi/archive/mcp/`) - A Ruby HTTP client for the Magi Archive API with authentication, retry logic, and role-based access control
2. **MCP Protocol Server** (`lib/magi/archive/mcp/server/tools/`) - Model Context Protocol tools that enable Claude Desktop, Codex, and other MCP clients to interact with Magi Archive

The client library connects to the **Magi Archive API server** (separate repository), which provides the actual backend services. This package makes those services accessible through both Ruby code and MCP-compatible AI assistants.

**Current Implementation: Phase 2** - Core functionality complete and production-ready.

**Key Features (Phase 2):**
- **Role-Based Security**: Three-tier access control (User, GM, Admin) with RS256 JWT authentication
- **Card Operations**: Full CRUD operations for cards with role enforcement
- **Batch Processing**: Bulk create/update operations with partial failure handling
- **Format Conversion**: HTML ↔ Markdown rendering
- **Children Management**: List and create child cards using compound naming
- **CLI Tool**: Command-line interface for testing and interactive use

**New Features (Phase 2.1):**
- **Admin Database Backup**: Create, download, list, and delete database backups
- **Card Relationships**: Explore card connections (referers, nests, links, linked_by, nested_in)
- **Tag Search**: Convenient tag-based search with AND/OR logic and pattern matching
- **Tag Validation**: Validate tags based on card type with content-based suggestions
- **Structure Recommendations**: Get comprehensive structure recommendations to prevent hallucinations
- **Weekly Summary Generation**: Automated weekly summaries combining wiki changes and repository activity
- **🆕 MCP Protocol Tools**: Full Model Context Protocol server for Claude Desktop and Codex

See [MCP_SERVER.md](MCP_SERVER.md) for complete installation, authentication, tools reference, and usage guide.

**Coming in Phase 3:**
- Safe CQL (Card Query Language) queries with enforced limits
- Async job management (spoiler scanning, bulk operations)
- Advanced search and filtering

## Quick Start: MCP Protocol Integration

Want to use Magi Archive directly in Claude Desktop, Claude Code, Codex, or ChatGPT Desktop?

**For ChatGPT Desktop (via npm + custom connector):**
```bash
# 1. Install the MCP server globally
npm install -g @magi-agi/mcp-server

# 2. Set environment variables (Windows PowerShell)
$env:MCP_USERNAME="your-username"
$env:MCP_PASSWORD="your-password"

# Or for Linux/Mac (bash/zsh)
export MCP_USERNAME=your-username
export MCP_PASSWORD=your-password

# 3. In ChatGPT Desktop:
#    - Go to Settings → Connectors → Create
#    - Configure the custom connector (see below)
```

**ChatGPT Desktop Connector Configuration:**
1. Open ChatGPT Desktop
2. Navigate to **Settings → Connectors → Create**
3. Configure the connector:
   - **Name**: Magi Archive
   - **Command**: `magi-archive-mcp`
   - **Environment Variables**:
     - `MCP_USERNAME`: your Decko wiki username
     - `MCP_PASSWORD`: your Decko wiki password
4. Save and the server will be available immediately

**Note**: The server will also be available via the official MCP registry soon.

**For Claude Desktop, Claude Code, or Codex:**
```bash
git clone https://github.com/your-org/magi-archive-mcp.git
cd magi-archive-mcp
bundle install

# Choose your client:
ruby bin/install-claude-desktop      # For Claude Desktop
ruby bin/install-claude-code         # For Claude Code (VS Code)
ruby bin/install-codex               # For Codex CLI
ruby bin/install-chatgpt             # For ChatGPT Desktop (alternative setup)
```

The installer configures your client automatically. Restart and start using all 16 Magi Archive tools!

**Available Tools:** get_card, search_cards, create_card, update_card, delete_card, list_children, get_tags, search_by_tags, get_relationships, validate_card, get_recommendations, get_types, render_content, admin_backup, create_weekly_summary, and more.

See [MCP_SERVER.md](MCP_SERVER.md) for complete guide including authentication, security, deployment, and troubleshooting.

## Installation

### As a Gem (Recommended)

```bash
gem install magi-archive-mcp
```

### From Source

```bash
git clone https://github.com/your-org/magi-archive-mcp.git
cd magi-archive-mcp
bundle install
bundle exec rake install
```

### Via npm (For ChatGPT Desktop)

ChatGPT Desktop uses npm packages for MCP server discovery. Install globally:

```bash
npm install -g @magi-agi/mcp-server
```

**Prerequisites:**
- Node.js 16+ and npm
- Ruby 2.7+ with Bundler

The npm package will automatically:
1. Check for Ruby and Bundler
2. Install Ruby dependencies via `bundle install`
3. Make the MCP server available to ChatGPT Desktop

**Configuration:**
Set environment variables before using:

```bash
# ~/.bashrc or ~/.zshrc
export MCP_USERNAME=your-decko-username
export MCP_PASSWORD=your-decko-password
# Or use API key:
# export MCP_API_KEY=your-key
# export MCP_ROLE=user
```

ChatGPT Desktop will automatically discover the server. Restart ChatGPT Desktop after installation.

### Development Setup

```bash
git clone https://github.com/your-org/magi-archive-mcp.git
cd magi-archive-mcp
bundle install
```

## Configuration

### Two Authentication Methods

#### Method 1: Username/Password (Recommended for Human Users)

Use your existing Decko wiki credentials - no API key needed!

```bash
# .env file
MCP_USERNAME=your-decko-username
MCP_PASSWORD=your-decko-password
DECKO_API_BASE_URL=https://wiki.magi-agi.org/api/mcp

# Optional: Override role (auto-detected from your permissions if not specified)
# MCP_ROLE=user
```

**Benefits:**
- ✅ No admin intervention needed
- ✅ Automatic role detection from your account permissions
- ✅ Same credentials as your wiki login
- ✅ Better audit trail (actions tied to your user account)

#### Method 2: API Key (For Service Accounts/Automation)

For bots, scripts, and automated processes:

```bash
# .env file
MCP_API_KEY=your-64-char-api-key
MCP_ROLE=user              # Required with API key
DECKO_API_BASE_URL=https://wiki.magi-agi.org/api/mcp
```

**Getting an API Key:**
Contact your Decko administrator to generate an API key for service accounts.

## Usage

### As a Library

#### Basic Card Operations

```ruby
require "magi/archive/mcp"

# Initialize tools (uses environment variables for config)
tools = Magi::Archive::Mcp::Tools.new

# Get a card
card = tools.get_card("Main Page")
puts card["name"]
puts card["content"]

# Search for cards
results = tools.search_cards(q: "quantum", type: "Article", limit: 10)
results["cards"].each do |card|
  puts "#{card['name']} (#{card['type']})"
end

# Create a card (requires appropriate role)
new_card = tools.create_card(
  "My New Card",
  content: "This is the content.",
  type: "Article"
)

# Update a card
updated = tools.update_card("My New Card", content: "Updated content.")

# Delete a card (admin only)
tools.delete_card("My New Card", force: false)
```

#### Pagination

```ruby
# Iterate through all matching cards
tools.each_card_page(q: "research", limit: 50) do |page|
  page["cards"].each do |card|
    puts card["name"]
  end
  puts "Offset: #{page['offset']}, Total: #{page['total']}"
end
```

#### Batch Operations

```ruby
# Per-item mode: each operation independent
operations = [
  { action: "create", name: "Card 1", content: "Content 1" },
  { action: "create", name: "Card 2", content: "Content 2" },
  { action: "update", name: "Existing Card", content: "New content" }
]

result = tools.batch_operations(operations, mode: "per_item")
result["results"].each do |op_result|
  puts "#{op_result['action']} #{op_result['name']}: #{op_result['status']}"
end

# Transactional mode: all or nothing
result = tools.batch_operations(operations, mode: "transactional")

# Create child cards using helper
ops = [
  tools.build_child_op("Business Plan", "Overview", content: "Executive summary"),
  tools.build_child_op("Business Plan", "Goals", content: "Key objectives"),
  tools.build_child_op("Business Plan", "Timeline", content: "Project schedule")
]
result = tools.batch_operations(ops)
```

#### Format Conversion

```ruby
# Markdown to HTML
html = tools.render_snippet("# Hello\n\nThis is **bold**.", from: :markdown, to: :html)

# HTML to Markdown
markdown = tools.render_snippet("<h1>Hello</h1><p>This is <strong>bold</strong>.</p>", from: :html, to: :markdown)
```

#### Weekly Summary Generation

```ruby
# Create a weekly summary card
card = tools.create_weekly_summary

# With custom options
card = tools.create_weekly_summary(
  base_path: "/path/to/repos",
  days: 7,
  date: "2025 12 09",
  executive_summary: "Custom summary..."
)
```

See [MCP_SERVER.md](MCP_SERVER.md#weekly-summary-feature) for complete documentation.

### Using the CLI

The `magi-archive-mcp` CLI provides command-line access to all MCP tools.

#### Get a Card

```bash
magi-archive-mcp get "Main Page"
magi-archive-mcp get --name "Main Page" --with-children
magi-archive-mcp get "Card Name" --format json
```

#### Search Cards

```bash
magi-archive-mcp search --query "quantum physics"
magi-archive-mcp search --type Article --limit 20
magi-archive-mcp search -q "research" -t Article -l 10 -o 20
```

#### Create a Card

```bash
magi-archive-mcp create --name "New Article" --content "Content here" --type Article
```

#### Update a Card

```bash
magi-archive-mcp update "Card Name" --content "Updated content"
magi-archive-mcp update --name "Card Name" --type "Article"
```

#### Delete a Card (Admin only)

```bash
magi-archive-mcp delete "Card Name"
magi-archive-mcp delete "Card With Children" --force
```

#### List Card Types

```bash
magi-archive-mcp types
magi-archive-mcp types --limit 100
```

#### Render Content

```bash
magi-archive-mcp render --from markdown --to html --content "# Hello"
magi-archive-mcp render --from html --to markdown --content "<h1>Hello</h1>"
```

#### List Children

```bash
magi-archive-mcp children "Parent Card"
magi-archive-mcp children --name "Parent Card" --limit 50
```

#### CLI Options

```
Usage: magi-archive-mcp COMMAND [options]

Commands:
  get NAME              Get a card by name
  search                Search for cards
  create                Create a new card
  update NAME           Update an existing card
  delete NAME           Delete a card (admin only)
  types                 List card types
  render                Convert HTML/Markdown
  children PARENT       List child cards

Options:
  -n, --name NAME              Card name
  -q, --query QUERY            Search query
  -t, --type TYPE              Card type
  -c, --content CONTENT        Card content
  -l, --limit NUM              Result limit (default: 50)
  -o, --offset NUM             Result offset (default: 0)
  -f, --format FORMAT          Output format (json|pretty)
      --from FORMAT            Source format for rendering
      --to FORMAT              Target format for rendering
      --with-children          Include children in get
      --force                  Force delete even with children
      --debug                  Show debug information
  -h, --help                   Show this help
  -v, --version                Show version
```

## Architecture

### Three-Role Security Model

1. **User Role (`mcp-user`)**:
   - Read public cards
   - Create/update own cards
   - No GM content visibility
   - No destructive operations

2. **GM Role (`mcp-gm`)**:
   - All User permissions
   - Read GM-only content
   - No destructive operations

3. **Admin Role (`mcp-admin`)**:
   - Full access to all cards
   - Delete and move operations
   - System administration

### Authentication Flow

1. Client library reads credentials from environment (API key or username/password)
2. Client library calls `POST /api/mcp/auth` on the Magi Archive API server
3. API server issues short-lived RS256 JWT (15-60 min expiry)
4. JWT includes claims: `sub`, `role`, `iss`, `iat`, `exp`, `jti`, `kid`
5. Client library verifies JWT signature via API server's JWKS endpoint
6. Client library automatically refreshes token before expiry

### Magi Archive API Server Endpoints

The client library connects to these endpoints on the Magi Archive API server (separate repository). All requests require `Authorization: Bearer <jwt_token>`:

**Phase 2 (Currently Implemented):**
- `POST /api/mcp/auth` - Get role-scoped JWT
- `GET /api/mcp/cards/:name` - Fetch card
- `GET /api/mcp/cards/:name/children` - List child cards
- `GET /api/mcp/cards` - Search/list cards
- `POST /api/mcp/cards` - Create card
- `PATCH /api/mcp/cards/:name` - Update card
- `DELETE /api/mcp/cards/:name` - Delete card (admin only)
- `POST /api/mcp/cards/batch` - Bulk operations
- `POST /api/mcp/render` - HTML→Markdown conversion
- `POST /api/mcp/render/markdown` - Markdown→HTML conversion

**Phase 3 (Coming Soon):**
- `POST /api/mcp/run_query` - Safe CQL queries with enforced limits
- `POST /api/mcp/jobs/spoiler-scan` - Start spoiler scan job
- `GET /api/mcp/jobs/:id` - Get job status
- `GET /api/mcp/jobs/:id/result` - Get job result

## Development

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run with documentation format
bundle exec rspec --format documentation

# Run specific file
bundle exec rspec spec/magi/archive/mcp/tools_spec.rb

# Run specific test
bundle exec rspec spec/magi/archive/mcp/tools_spec.rb:42
```

**Test Coverage:** 102 examples, 0 failures (Phase 2 implementation)
- Unit Tests (95 examples):
  - Config: 17 examples
  - Auth: 18 examples
  - Client: 18 examples
  - Tools: 41 examples (Phase 2 tools only)
  - Main: 1 example
- Integration Tests (7 examples):
  - Contract tests with recorded response shapes
  - Validates API response formats and error handling
  - Catches schema drift between client and server

**Note:** Integration tests currently use WebMock with recorded response shapes from the live Decko MCP server. For full end-to-end testing, run against a staging Decko instance.

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix style issues
bundle exec rubocop -a
```

### Build & Install Locally

```bash
# Build gem
bundle exec rake build

# Install locally
bundle exec rake install

# Interactive console
bundle exec rake console
```

### Project Structure

```
lib/magi/archive/
├── mcp/
│   ├── server.rb          # MCP protocol server (JSON-RPC over stdio)
│   ├── tools.rb           # MCP tool implementations
│   ├── client.rb          # HTTP client for Magi Archive API
│   ├── auth.rb            # JWT verification logic
│   ├── config.rb          # Configuration management
│   └── version.rb         # Version constant
└── mcp.rb                 # Main module

bin/
└── magi-archive-mcp       # CLI executable

spec/
├── magi/archive/          # Unit tests
├── integration/           # Contract tests with recorded responses
│   └── contract_spec.rb   # API response shape validation
└── support/               # Test helpers and fixtures
```

## Error Handling

The client raises specific exceptions for different error conditions:

```ruby
begin
  card = tools.get_card("Nonexistent Card")
rescue Magi::Archive::Mcp::Client::NotFoundError => e
  puts "Card not found: #{e.message}"
rescue Magi::Archive::Mcp::Client::AuthorizationError => e
  puts "Permission denied: #{e.message}"
rescue Magi::Archive::Mcp::Client::ValidationError => e
  puts "Validation error: #{e.message}"
  puts "Details: #{e.details.inspect}"
rescue Magi::Archive::Mcp::Client::APIError => e
  puts "API error: #{e.message}"
end
```

**Exception Types:**
- `NotFoundError` - Resource not found (404)
- `AuthorizationError` - Permission denied (401, 403)
- `ValidationError` - Invalid input (422)
- `RateLimitError` - Rate limit exceeded (429)
- `APIError` - General API errors (400, 500-series)

## Security Best Practices

1. **Never commit credentials**: Use `.env` files (gitignored) for sensitive data
2. **Use minimal role**: Request only the role needed for your operations
3. **Token management**: Library handles refresh automatically
4. **HTTPS only**: Always use secure connections to Decko
5. **Input validation**: Sanitize user inputs before API calls
6. **Rate limiting**: Respect API rate limits (enforced server-side)

See [MCP_SERVER.md](MCP_SERVER.md#security-best-practices) for comprehensive security guidelines.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Make changes and add tests
4. Run tests and RuboCop (`bundle exec rspec && bundle exec rubocop`)
5. Commit with clear messages
6. Push to your fork and submit a pull request

## Documentation

- **[MCP Server Guide](MCP_SERVER.md)** - Complete guide: installation, authentication, tools reference, security, deployment, troubleshooting
- **[MCP Specification](MCP-SPEC.md)** - API specification and protocol details
- **[Development Guide](AGENTS.md)** - Ruby development guidelines and project structure
- **[Claude Code Guide](CLAUDE.md)** - Development guidance for AI-assisted coding
- **[API Documentation](https://rubydoc.info/gems/magi-archive-mcp)** - YARD documentation

## License

MIT License - see [LICENSE](LICENSE) file for details

## Support

- **Issues**: [GitHub Issues](https://github.com/your-org/magi-archive-mcp/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/magi-archive-mcp/discussions)
- **Email**: support@magi-agi.org

## Version History

### v0.1.0 - Initial Release (December 2024)

**Phase 1: Core Infrastructure**
- JWT authentication with RS256 verification
- Role-based access control (User, GM, Admin)
- HTTP client with automatic retry and token refresh
- Comprehensive error handling

**Phase 2: MCP Tools**
- 16 complete MCP tools for card operations, search, tags, relationships, validation, and admin functions
- MCP Server implementation with JSON-RPC 2.0 over stdio
- Auto-installers for Claude Desktop, Claude Code, Codex, and ChatGPT
- Weekly summary generation with git repository scanning

**Phase 2.1: Advanced Features**
- Username/password authentication (in addition to API keys)
- Database backup management (admin)
- Card relationship exploration (referers, nests, links)
- Tag validation and structure recommendations
- Content rendering (HTML ↔ Markdown)

**Testing & Documentation**
- 102 RSpec tests (100% passing)
- Comprehensive MCP Server guide
- Complete tools reference
- Security best practices

## Related Projects

- [Magi Archive](https://github.com/your-org/magi-archive) - The Decko application
- [MCP Specification](https://modelcontextprotocol.io) - Model Context Protocol

---

**Version:** 0.1.0
**Ruby:** 3.2+
**Maintained by:** Magi AGI Team
