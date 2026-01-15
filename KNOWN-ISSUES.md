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

**Status**: Under Investigation

**Observed Behavior**:
- MCP tools work initially but fail after sustained use
- Tools require manual reset to resume functioning
- Appears to be related to ChatGPT's internal rate limiting of MCP tool invocations

**Root Cause Analysis**:
ChatGPT's MCP connector has undocumented rate limits on tool calls. When the Magi Archive MCP server is called too frequently or returns responses that are too large, ChatGPT's internal system may throttle or block subsequent tool calls.

This is NOT our API rate limiting - it's ChatGPT's client-side rate limiting of its own MCP tool invocation mechanism.

**Potential Factors**:
1. **Response size**: Large card content or search results may trigger limits
2. **Call frequency**: Rapid successive tool calls may exceed limits
3. **Token count**: Total tokens in tool responses may hit ChatGPT's context limits

**Proposed Mitigations**:

#### Option A: Response Size Limits
Add configurable response truncation:
```ruby
# In tools.rb - truncate large content
def get_card(name, max_content_length: 5000)
  card = client.get_card(name)
  if card["content"]&.length > max_content_length
    card["content"] = card["content"][0...max_content_length] + "\n\n[Content truncated. Use offset to retrieve more.]"
  end
  card
end
```

#### Option B: Search Result Limits
Reduce default search limits for ChatGPT:
```ruby
# Detect ChatGPT client and adjust limits
DEFAULT_SEARCH_LIMIT = 20  # Instead of 50
```

#### Option C: Batched Responses
For large operations, return partial results with continuation tokens:
```ruby
{
  "cards" => first_10_cards,
  "has_more" => true,
  "continuation_token" => "abc123"
}
```

#### Option D: Client-Specific Configuration
Allow per-client configuration in environment:
```bash
CHATGPT_MAX_RESPONSE_SIZE=5000
CHATGPT_MAX_SEARCH_RESULTS=10
CHATGPT_DELAY_BETWEEN_CALLS_MS=500
```

**User Workarounds**:
1. Use smaller, more specific queries
2. Reset MCP tools when they stop responding (in ChatGPT settings)
3. Break large operations into multiple smaller requests
4. Consider using Claude Desktop for heavy wiki operations

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
