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

## 2. ChatGPT MCP Bridge Instability

### Issue: MCP tools fail with "Resource not found" errors in ChatGPT

**Status**: Confirmed ChatGPT Client-Side Issue (Not Rate Limiting)

**Observed Behavior**:
- Tools work initially, then fail with `Resource not found: .../link_<hash>/tool_name`
- Tool registry becomes **empty** after failures (not rate limited)
- Reads often succeed while writes fail
- Refreshing tools sometimes restores functionality, sometimes shows empty registry
- Tools disappear from interface requiring manual reset

**Root Cause (Confirmed through testing)**:

This is **NOT** a rate limit or token limit issue. It's ChatGPT's internal MCP bridge
losing the tool routing handle (`link_<hash>`) mid-session.

Evidence:
1. Error is "Resource not found" not "rate limit" or "quota exceeded"
2. After failure, `list_resources` returns `{"finite": true}` with **no tools**
3. Small payloads (~650 tokens) fail the same as large ones
4. Single read + single write can trigger the failure
5. The `link_<hash>` handle can change or become invalid between calls

This matches reports in the [OpenAI Community Thread](https://community.openai.com/t/mcp-server-tools-now-in-chatgpt-developer-mode/1357233/81):
- "ResourceNotFound ... link_<hash> ..." even when tools are listed
- "Works better with fewer tools"
- Tool registry desyncing mid-conversation

### Recommended Workflow for ChatGPT Users

#### Preflight Check Before Writes
```
1. Run list_resources(only_tools=true, refetch_tools=true)
2. If tools are NOT listed → reset/reconnect tools first
3. If tools ARE listed → proceed with ONE write, then stop
```

#### One Write Per Stable Window
Even if tools exist, do at most **one write** before re-checking the registry.
Writes seem to trigger the registry drop more than reads.

#### Use batch_cards for Multiple Updates
Instead of multiple `update_card` calls:
```ruby
# BAD: Multiple writes = multiple chances for registry to drop
update_card(name: "Card1", content: "...")
update_card(name: "Card2", content: "...")  # May fail

# GOOD: Single write for multiple cards
batch_cards(operations: [
  {action: "update", name: "Card1", content: "..."},
  {action: "update", name: "Card2", content: "..."}
])
```

#### Minimize Enabled Tools
Disable unused tools on the connector. Community reports reliability improving
when reducing tool count (some users had 70+ tools causing issues).

#### Reset Tools When Needed
Use ChatGPT's "refresh tools / toggle tools" UI to re-sync the connector
when tools stop responding.

### Response Size Optimizations (Still Helpful)

While not the root cause, smaller responses reduce bridge overhead:

| Tool | Parameter | Default |
|------|-----------|---------|
| `get_card` | `max_content_length` | 8000 chars |
| `fetch` | `max_content_length` | 8000 chars |
| `get_revision` | `max_content_length` | 8000 chars |
| `render_content` | `max_output_length` | 8000 chars |
| `search_cards` | `limit` | 20 results |
| `list_children` | `limit` | 20 results |
| `run_query` | `limit` | 20 results |

All content-returning tools support pagination via `content_offset` parameter.

### Alternative: Use Claude Desktop for Heavy Work

Claude Desktop's MCP implementation is more stable for sustained wiki operations.
Consider using ChatGPT for reads/exploration and Claude Desktop for bulk writes.

### References

- [OpenAI Community Thread](https://community.openai.com/t/mcp-server-tools-now-in-chatgpt-developer-mode/1357233/81)
- [OpenAI MCP Documentation](https://platform.openai.com/docs/guides/tools-connectors-mcp)

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
