# Server-Side Bugs Found During Integration Testing

This document tracks bugs discovered in the `magi-archive` server (wiki.magi-agi.org) during MCP client integration testing.

## Bug #1: `/cards/:name/children` Endpoint Returns NoMethodError

**Severity**: HIGH
**Impact**: `list_children` API completely unusable
**Status**: Confirmed - Affects ALL card names

### Description

The `/cards/:name/children` endpoint returns HTTP 500 with `NoMethodError` exception for all requests, regardless of card name format.

### Reproduction

```bash
# Using integration tests
INTEGRATION_TEST=true bundle exec rspec spec/integration/debug_list_children_spec.rb
```

### Test Results

All card name formats fail:
- ❌ Simple names: `Home` → NoMethodError
- ❌ Names with spaces: `Main Page` → 404 Not Found (expected) or NoMethodError
- ❌ Compound names: `Games+Butterfly Galaxii` → NoMethodError
- ❌ Newly created cards: `DebugParent1234567` → NoMethodError

### Expected Behavior

The endpoint should return:
```json
{
  "parent": "CardName",
  "children": [
    {
      "name": "CardName+Child1",
      "content": "...",
      "type": "RichText",
      "id": 123
    }
  ],
  "child_count": 1,
  "depth": 1,
  "limit": 50,
  "offset": 0
}
```

### Actual Behavior

```json
{
  "code": "internal_error",
  "message": "An unexpected error occurred",
  "details": {
    "exception": "NoMethodError"
  }
}
```

### Server Logs Needed

Please check Rails logs for the actual NoMethodError message and stack trace.

### Client-Side Workaround

None available. The MCP client integration test for `list_children` is skipped until this is fixed:

```ruby
it "lists children of a parent card", skip: "Server returns NoMethodError - needs server-side fix" do
  # Test implementation
end
```

### Related Files

- **Client test**: `spec/integration/full_api_integration_spec.rb:158`
- **Debug test**: `spec/integration/debug_list_children_spec.rb`
- **Contract test** (passes with mocked response): `spec/integration/contract_spec.rb:76`

### Suggested Fix

The endpoint is likely missing implementation or has a typo in the controller. Check:

1. **Routing**: Is `/api/mcp/cards/:name/children` properly routed?
2. **Controller**: Does the controller action exist and is it calling the correct method?
3. **Decko Card API**: Is there a method name mismatch (e.g., `children` vs `kids` vs `child_cards`)?

### Priority

**HIGH** - This is a documented MCP endpoint that should be functional. The contract test shows the expected format is correct; the server implementation is broken.

---

## Bug #2: `/cards/batch` Missing `mode` Field in Response

**Severity**: LOW
**Impact**: Response doesn't include requested mode, but behavior is correct
**Status**: Workaround implemented

### Description

When calling `/cards/batch` with `mode: "transactional"`, the server correctly implements transactional behavior (rollback on failure) but doesn't include the `mode` field in the response.

### Reproduction

```ruby
result = tools.batch_operations(operations, mode: "transactional")
# result["mode"] is nil, not "transactional"
```

### Expected Behavior

```json
{
  "results": [...],
  "mode": "transactional",
  "total": 2,
  "succeeded": 0,
  "failed": 2
}
```

### Actual Behavior

```json
{
  "results": [...],
  "total": 2,
  "succeeded": 0,
  "failed": 2
}
```

Note: The `mode` field is missing, but transactional rollback DOES work correctly.

### Workaround

The client test verifies transactional behavior by checking that rolled-back cards don't exist:

```ruby
# Don't check mode field, verify behavior instead
expect {
  tools.get_card("#{batch_prefix}_good")
}.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
```

### Priority

**LOW** - Behavior is correct, just missing response field. Not blocking.

---

## Testing Process

### Integration Test Coverage

As of 2025-12-08:
- **12/12 functional tests passing** (100%)
- **2 pending tests** (documented above)
- **6 retry logic unit tests** added (all passing)

### How Bugs Were Found

1. **Contract tests** (mocked responses) passed ✅
2. **Integration tests** (real server) failed ❌
3. **Lesson**: Contract tests verify client correctness, integration tests verify server correctness

### Recommendation

Add server-side integration tests for the MCP API endpoints to catch these issues before client testing.

---

## Contact

For questions about these bugs, see:
- **Client implementation**: `magi-archive-mcp` repository
- **Server implementation**: `magi-archive` repository
- **MCP Specification**: `MCP-SPEC.md`

## Last Updated

2025-12-08 - Initial bug report after comprehensive integration testing
