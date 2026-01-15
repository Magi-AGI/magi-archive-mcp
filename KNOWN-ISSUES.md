# Known Issues and Investigation Notes

**Last Updated**: 2025-01-15

This document tracks known issues, behaviors under investigation, and planned improvements.

---

## 1. Role/Permission Investigation

### Issue: Users with "user" role can see/edit GM-only content

**Status**: Under Investigation

**Observed Behavior**:
- Users configured with `MCP_ROLE=user` or using username/password auth that should resolve to "user" role can still view and update GM-only cards.
- Expected: Cards with `+GM` or `+AI` suffixes should return 404 for user role.

**Possible Causes** (to investigate):
1. **Decko permission detection**: The Decko API may be detecting the actual user's wiki permissions rather than respecting the MCP role parameter
2. **Token role claim**: The JWT issued by Decko may contain elevated permissions based on the user's wiki account
3. **Endpoint-specific overrides**: Some endpoints may bypass role filtering

**Investigation Steps**:
1. Check JWT claims returned by `/api/mcp/auth` for actual role value
2. Test with a user account that has no GM permissions in the wiki
3. Review Decko's `MCP::McpController` role enforcement logic
4. Compare behavior between API key auth and username/password auth

**Workaround**: None currently - be aware that role filtering may not work as documented.

**Related**: Consider merging OAuth with Decko user authentication to leverage proper wiki permissions through standard OAuth flows.

---

## 2. ChatGPT Integration Rate Limiting

### Issue: MCP tools fail regularly when used with ChatGPT Desktop/Web/Mobile

**Status**: Mitigations Implemented (Monitoring)

**Observed Behavior**:
- MCP tools work initially but fail after sustained use
- Tools disappear from interface or hang/timeout
- Tools require manual reset to resume functioning
- Triggered by: large responses, many successive calls, or unpredictable factors

**Root Cause Analysis**:
ChatGPT's MCP connector has limits on tool calls. Per [OpenAI's MCP documentation](https://cookbook.openai.com/examples/mcp/mcp_tool_guide):

1. **Tool schema limit**: All tool definitions must be < 5000 tokens combined
2. **Response overhead**: Large responses consume context tokens and increase latency
3. **Verbose data**: Returning full records (instead of relevant fields) causes issues

This is NOT our API rate limiting - it's ChatGPT's client-side constraints on MCP tool invocations.

### Implemented Mitigations (v1.x.x)

#### Content Truncation (get_card)
The `get_card` tool now accepts `max_content_length` parameter:
```ruby
# Default: 8000 characters to prevent oversized responses
get_card(name: "Some Card", max_content_length: 8000)

# Use 0 for unlimited (may cause ChatGPT issues with large cards)
get_card(name: "Some Card", max_content_length: 0)
```

#### Reduced Default Limits
- `search_cards`: Default limit reduced from 50 to 20
- `list_children`: Default limit reduced from 50 to 20

These can still be overridden for clients that support larger responses.

### Best Practices from OpenAI

Per [OpenAI Cookbook MCP Guide](https://cookbook.openai.com/examples/mcp/mcp_tool_guide):
- Keep tool descriptions crisp: 1-2 sentences
- Return only relevant fields, not entire data objects
- Use `allowed_tools` parameter to limit exposed tools
- Avoid verbose definitions that add hundreds of tokens

### Future Improvements (Planned)

#### Option A: Client-Specific Configuration
Allow per-client limits in environment:
```bash
CHATGPT_MAX_CONTENT_LENGTH=5000
CHATGPT_MAX_SEARCH_RESULTS=10
```

#### Option B: Streaming Responses
Implement streaming for large responses to avoid timeouts.

#### Option C: Tool Schema Optimization
Review and optimize tool descriptions to reduce token count.

**User Workarounds**:
1. Use `max_content_length` parameter for large cards
2. Use smaller limits in queries (e.g., `limit: 10`)
3. Reset MCP tools when they stop responding (ChatGPT settings)
4. Break large operations into multiple smaller requests
5. Consider Claude Desktop for heavy wiki operations

---

## 3. Installation Issues

### Windows Path Handling

**Status**: Known Issue

**Description**: Installation scripts use forward slashes which work in most cases on Windows via MSYS/Git Bash, but may cause issues in pure Windows environments.

**Workaround**: Use Git Bash or WSL for installation, or manually adjust paths in config files.

### Password Input on Windows

**Status**: Known Issue

**Description**: The `stty -echo` command for hiding password input doesn't work in native Windows CMD/PowerShell.

**Workaround**: The installers detect Windows and skip password hiding. Passwords are visible during entry in native Windows terminals.

---

## 4. OAuth/Authentication Improvements

### Planned: Merge OAuth with Decko Authentication

**Status**: Planned

**Description**: Currently, the MCP server has its own auth flow that authenticates against Decko's `/api/mcp/auth` endpoint. ChatGPT and other platforms that expect standard OAuth flows (authorization code, token exchange) cannot directly authenticate users.

**Proposed Solution**:
1. Implement standard OAuth 2.0 authorization code flow
2. Redirect users to Decko's login page
3. Exchange authorization code for JWT token
4. Map Decko user permissions to MCP roles automatically

**Benefits**:
- Users log in once with their wiki credentials
- Proper permission inheritance from wiki account
- Compatible with ChatGPT's expected OAuth flow
- Better audit trail (actions tied to actual users)

**Implementation Complexity**: Medium-High (requires changes to both MCP server and Decko)

---

## 5. Virtual Card Handling

### Issue: `with_children` doesn't return virtual cards

**Status**: By Design (Documented)

**Description**: The `get_card(name, with_children: true)` parameter only returns database-stored child cards, not virtual cards created on-demand by Decko.

**Workaround**: Use `list_children(parent_name)` which explicitly queries for child relationships.

**Documentation**: See `CHATGPT-USAGE-GUIDE.md` section 4.

---

## Reporting New Issues

If you discover a new issue:
1. Check this document first
2. Review `CHATGPT-USAGE-GUIDE.md` for common mistakes
3. Open a GitHub issue with:
   - Steps to reproduce
   - Expected vs actual behavior
   - Client used (Claude Desktop, ChatGPT, etc.)
   - Role and authentication method
   - Any error messages

---

## Version History

- 2025-01-15: Initial document with role investigation, ChatGPT rate limiting, installation issues
