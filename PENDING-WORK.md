# Pending Work & Issues

This document tracks remaining work items and known issues after the integration test implementation phase.

## ✅ Completed Work (2025-12-08)

### Integration Testing
- ✅ Fixed all integration test failures (12/12 passing)
- ✅ Added 6 comprehensive retry logic unit tests
- ✅ Created `TESTING-GAPS.md` tracking document
- ✅ Created `SERVER-BUGS.md` for server team
- ✅ Implemented missing `spoiler_scan` method
- ✅ Fixed card type issues (Basic → RichText)
- ✅ Verified transactional mode works correctly
- ✅ Added `list_children` integration test (found server bug)

### Test Results Summary
- **Unit Tests**: 178 passing (includes 6 new retry tests)
- **Integration Tests**: 12 passing, 2 appropriately pending
- **Contract Tests**: 1 passing
- **Total**: 191 examples, 0 failures, 19 pending

## 🔴 Critical Server Bugs (Blocking)

### Bug #1: `/cards/:name/children` Endpoint - NoMethodError
**Status**: BLOCKING - Endpoint completely broken
**Impact**: `list_children` API unusable
**Details**: See `SERVER-BUGS.md`
**Server Action Required**: Fix controller implementation

### Bug #2: Admin API Key Endpoints
**Status**: BLOCKING - Routes not wired up
**Impact**: Admin endpoints unreachable
**Details**: From Codex review:
- Controller targets `McpApiKey` (ActiveRecord) but should use `Mcp::ApiKeyManager` (Cards)
- No `/api/mcp/admin/*` routes in `config/routes.rb`
**Server Action Required**:
1. Align controller to `Mcp::ApiKeyManager`
2. Add admin namespace routes

### Bug #3: Rate Limiting - Wrong retry_after Value
**Status**: HIGH - Affects client retry logic
**Impact**: Clients get bogus retry_after values
**Details**: `RateLimitable#time_until_reset` returns cached request count, not TTL
**Server Action Required**: Use cache TTL or store expiry timestamp

### Bug #4: skip_modules Parameter
**Status**: MEDIUM - May cause unknown attribute errors
**Impact**: `jobs_controller.rb` calls `Card.fetch(name, skip_modules: true)`
**Server Action Required**: Drop arg or guard it

## ⚠️ Client Issues (This Repo)

### Issue #1: Git Timeout Implementation
**Status**: ✅ ALREADY FIXED
**Details**: Code correctly uses `Timeout.timeout(30)` wrapper (tools.rb:1243)
**Note**: Codex may have reviewed older version before fix

### Issue #2: Integration Tests Not in CI
**Status**: MEDIUM - Tests won't run automatically
**Impact**: Server bugs could slip through
**Recommendation**: Enable `INTEGRATION_TEST=true` in CI or create separate CI job
**Options**:
1. Add CI environment variable
2. Create `spec/integration_ci/` with always-run tests
3. Add make task: `make integration-test`

## 📋 Missing Integration Test Coverage

Only ~30% of API endpoints have integration tests. See `TESTING-GAPS.md` for full list.

### High Priority (Core API):
- [ ] `search_cards` - Fundamental search operation
- [ ] `render_snippet` - Content transformation
- [ ] `list_types` - Type discovery
- [ ] Tag operations - Content organization
- [ ] Relationship operations - Graph navigation

### Medium Priority (Advanced):
- [ ] Validation operations - Data integrity
- [ ] Weekly summary operations - Automated reporting

### Low Priority (Admin):
- [ ] Admin backup operations - Admin-only features

## 🔄 Server Actions Needed

### Immediate (Blocking Current Work):
1. **Fix `/cards/:name/children` endpoint** - NoMethodError prevents list_children usage
2. **Wire up admin routes** - Admin endpoints currently unreachable
3. **Fix rate limiting** - Wrong retry_after calculation

### Short Term (Should Fix Soon):
4. **Run server-side specs** - `bundle exec rspec spec/mcp_api` (needs DB env vars set in Linux/WSL)
5. **Fix skip_modules** - Guard or remove parameter
6. **Add server integration tests** - Prevent bugs before client testing

## 📝 Documentation Updates Needed

### This Repo (magi-archive-mcp):
- [x] `TESTING-GAPS.md` - Integration test coverage tracker
- [x] `SERVER-BUGS.md` - Server bug reports
- [ ] `README.md` - Update with new test instructions
- [ ] `CHANGELOG.md` - Document Phase 3 completion

### Server Repo (magi-archive):
- [ ] Document admin endpoint routes
- [ ] Document rate limiting fix
- [ ] Add MCP API integration test suite

## 🎯 Next Steps

### For Client Team (This Repo):
1. Review server bug fixes as they're deployed
2. Add integration tests for remaining endpoints (per `TESTING-GAPS.md`)
3. Consider enabling integration tests in CI
4. Update documentation

### For Server Team (magi-archive):
1. **CRITICAL**: Fix `/cards/:name/children` NoMethodError
2. **CRITICAL**: Wire up admin API routes
3. Fix rate limiting retry_after calculation
4. Run `bundle exec rspec spec/mcp_api` to verify
5. Consider adding server-side integration tests for MCP API

## 📊 Success Metrics

- ✅ All unit tests passing (178/178)
- ✅ All functional integration tests passing (12/12)
- ⏸️ 2 tests appropriately pending (documented bugs/limitations)
- ⏸️ Server bugs documented and reported
- ⏸️ Test coverage tracking in place

## 🔗 Related Files

- `TESTING-GAPS.md` - Coverage tracking
- `SERVER-BUGS.md` - Bug reports
- `MCP-SPEC.md` - API specification
- `spec/integration/full_api_integration_spec.rb` - Main integration tests
- `spec/magi/archive/mcp/client_spec.rb` - Unit tests (includes retry logic)

## Last Updated

2025-12-08 - After comprehensive integration testing phase
