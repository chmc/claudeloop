# Issue #36: Wire OpenCode End-to-End (Phases 13-14)

## Context

Issue #36 is Step 5 of the provider abstraction epic (#31). Phases 1-12 have been completed — provider abstraction layer exists, OpenCode adapter with event normalizer is implemented, and unit tests pass. This issue completes the end-to-end wiring and adds integration test infrastructure.

## Current State Analysis

### Already Implemented ✓

| Component | Status | Location |
|-----------|--------|----------|
| Provider abstraction | ✓ | `lib/provider.sh` (92 lines) |
| OpenCode adapter | ✓ | `lib/adapters/opencode.sh` (193 lines) |
| OpenCode permission adapter | ✓ | `lib/adapters/permission_opencode.sh` |
| Event normalizer (AWK) | ✓ | `_opencode_normalize_events()` in opencode.sh |
| Execution wiring | ✓ | `lib/execution.sh:191` — uses `provider_cli`, `provider_exec_args`, `provider_normalize_events` |
| Verify wiring | ✓ | `lib/verify.sh:117` — uses provider functions |
| AI-parse wiring | ✓ | `lib/ai_parser.sh:39` — uses provider functions |
| Adapter unit tests | ✓ | `tests/test_opencode_adapter.sh` (428 lines, 45 tests) |
| Permission adapter tests | ✓ | `tests/test_opencode_permission.sh` |
| Event fixtures | ✓ | `tests/fixtures/opencode_events/` (7 files) |

### Missing ❌

| Component | Required For |
|-----------|--------------|
| `tests/fake_opencode` | Phase 14 — integration testing with OpenCode provider |
| Provider matrix in integration tests | Phase 14 — verify both providers work E2E |
| E2E verification | Phase 13 — confirm `PROVIDER=opencode` actually works |

## OpenCode Event Schema (from SDK types.gen.ts)

### Event Types for fake_opencode

| Event | When Emitted | Normalizes To |
|-------|--------------|---------------|
| `session.created` | Session start | `system` (init) |
| `message.part.updated` (text) | Assistant output | `assistant` |
| `message.part.updated` (tool) | Tool lifecycle | `tool_use` / `tool_result` |
| `session.idle` | Processing complete | `result` |
| `file.edited` | File modification | `tool_use` (Edit) |
| `permission.updated` | Permission request | `control_request` (not currently mapped) |

### Tool State Machine

```
pending → running → completed | error | failed
```

### Event Field Variations

fake_opencode must handle these field name variations (all supported by normalizer):

| Canonical | Alternatives |
|-----------|--------------|
| `callID` | `call_id`, `toolCallId` |
| `name` | `toolName`, `tool` |
| `output` | `result`, `content` |
| `state` | `status` |

### CLI Flags

```sh
opencode run --format json [message]
opencode run --format json --dangerously-skip-permissions [message]
```

## Implementation Plan

### Phase 13: Verify E2E Wiring (1 hour)

**Goal:** Confirm `PROVIDER=opencode` works through full pipeline.

1. **Manual E2E test** — run with real opencode binary (if available) or mock
2. **Check provider detection** — verify `provider_detect` returns "opencode"
3. **Verify normalizer in pipeline** — confirm events flow through `provider_normalize_events`

No code changes expected — just verification that existing wiring works.

### Phase 14: Create fake_opencode (4-6 hours)

**Goal:** Mirror `fake_claude` capabilities with OpenCode event format.

#### File: `tests/fake_opencode`

```sh
#!/bin/sh
# Fake OpenCode CLI for testing
# Emits OpenCode JSON events (NDJSON format)
# Configuration via $FAKE_OPENCODE_DIR (required)
```

#### Required Scenarios (mapped from fake_claude)

| Scenario | Claude Equivalent | Key Events |
|----------|-------------------|------------|
| `success` | `success` | session.created → text → tool (Edit) → session.idle |
| `success_multi` | `success_multi` | Multiple tools (Read → Edit → Bash) |
| `success_verbose` | `success_verbose` | Many tools, realistic output |
| `failure` | `failure` | session.created → error text → session.idle |
| `verify_pass` | `verify_pass` | Tool calls + "VERIFICATION_PASSED" in text |
| `verify_fail` | `verify_fail` | "VERIFICATION_FAILED" in text |
| `verify_skip` | `verify_skip` | No tool calls, just VERIFICATION_PASSED |
| `ai_parse` | `ai_parse` | Phase headers in text output |
| `quota_error` | `quota_error` | Rate limit error text |
| `permission_request` | `permission_request` | permission.updated event |
| `read_only` | `read_only` | Only Read/Grep tools (no writes) |
| `empty` | `empty` | No output |
| `slow` | `slow` | Sleep before output |
| `custom` | `custom` | Read from `custom_output` file |

#### Event Templates

**session.created:**
```json
{"type":"session.created","sessionId":"sess_001","model":"fake-opencode-v1"}
```

**message.part.updated (text):**
```json
{"type":"message.part.updated","text":"I will make changes."}
```

**message.part.updated (tool pending):**
```json
{"type":"message.part.updated","callID":"tool_001","name":"Edit","state":"pending"}
```

**message.part.updated (tool completed):**
```json
{"type":"message.part.updated","callID":"tool_001","name":"Edit","state":"completed","output":"ok"}
```

**message.part.updated (tool error):**
```json
{"type":"message.part.updated","callID":"tool_002","name":"Bash","state":"error","output":"command failed"}
```

**session.idle:**
```json
{"type":"session.idle","sessionId":"sess_001"}
```

**permission.updated (future):**
```json
{"type":"permission.updated","id":"perm_001","type":"bash","title":"Run: rm -rf /tmp","sessionID":"sess_001","callID":"tool_003"}
```

#### Integration Test Updates

Modify `tests/test_integration_basic.sh` and other integration tests:

```sh
# Add to setup()
_write_opencode_stub() {
  # Similar to _write_claude_stub but uses fake_opencode
}

# Add provider matrix test
@test "integration: full pipeline works with PROVIDER=opencode" {
  export PROVIDER=opencode
  export PATH="$TEST_DIR/bin:$PATH"
  # ... test with fake_opencode
}
```

## Files to Create/Modify

| File | Action | Lines (est) |
|------|--------|-------------|
| `tests/fake_opencode` | CREATE | ~400 |
| `tests/test_integration_basic.sh` | MODIFY | +30 |
| `tests/test_integration_retry.sh` | MODIFY | +20 |

## Verification Plan

1. **Unit tests pass:**
   ```sh
   bats tests/test_opencode_adapter.sh
   bats tests/test_provider.sh
   ```

2. **fake_opencode scenarios work:**
   ```sh
   FAKE_OPENCODE_DIR=/tmp/test tests/fake_opencode  # success scenario
   ```

3. **Event normalization E2E:**
   ```sh
   FAKE_OPENCODE_DIR=/tmp/test tests/fake_opencode | \
     . lib/adapters/opencode.sh && _opencode_normalize_events
   ```

4. **Integration tests with both providers:**
   ```sh
   bats --filter-tags integration tests/test_integration_basic.sh
   PROVIDER=opencode bats --filter-tags integration tests/test_integration_basic.sh
   ```

5. **Full test suite:**
   ```sh
   ./tests/run_all_tests.sh
   ```

## Risks

- **Event schema drift:** OpenCode SDK types may change; fixtures need version tracking
- **Permission model gap:** OpenCode uses HTTP API for permissions vs Claude's FD7/FIFO — `permission.updated` events not currently mapped by normalizer (out of scope for Phase 14, tracked for future)

## Out of Scope

- HTTP-based permission handling (Phase 11 scope, already implemented separately)
- Server mode (`opencode serve`) integration
- CI provider matrix (`check-opencode-compat.yml`) — tracked in Phase 15-16

## Architecture Impact

**No architectural changes.** This issue completes wiring that's already designed:
- Provider abstraction layer exists (`lib/provider.sh`)
- Adapter pattern established (`lib/adapters/*.sh`)
- Event normalization pipeline in place

**New test infrastructure only:**
- `tests/fake_opencode` — parallel to existing `tests/fake_claude`
- Provider matrix in integration tests — env var based (`PROVIDER=opencode`)

## ADR

N/A — Architecture decision already documented in Phase 9 (issue #34). No new architectural decisions required for E2E wiring and test harness creation.

## Workflow / State Machines

**fake_opencode scenario selection** (same as fake_claude):
```
$FAKE_OPENCODE_DIR/scenarios (line N) → per-call override
$FAKE_OPENCODE_DIR/scenario → default
fallback → "success"
```

**OpenCode tool state machine** (emitted by fake_opencode):
```
pending → running → completed
                 → error
                 → failed
```

## Tests

| Test File | Changes |
|-----------|---------|
| `tests/fake_opencode` | NEW — 15+ scenarios mirroring fake_claude |
| `tests/test_integration_basic.sh` | ADD — `PROVIDER=opencode` test cases |
| `tests/test_integration_retry.sh` | ADD — retry tests with OpenCode |

**Test commands:**
```sh
# Verify fake_opencode works standalone
FAKE_OPENCODE_DIR=/tmp/test tests/fake_opencode

# Run integration tests with OpenCode
PROVIDER=opencode bats tests/test_integration_basic.sh

# Full suite (both providers)
./tests/run_all_tests.sh
```

## Documentation

N/A — Documentation updates are Phase 16 scope (issue #37). This issue is infrastructure only.

## Install / Uninstall

N/A — `tests/fake_opencode` is test infrastructure, not installed by `install.sh`. Packaging updates are Phase 15 scope (issue #37).

## Release

**Pre-merge verification:**
```sh
./tests/smoke.sh
bats tests/test_opencode_adapter.sh
bats tests/test_integration_basic.sh
```

**Release notes (for beta changelog):**
- OpenCode provider now works end-to-end with `--provider opencode`
- Added `fake_opencode` test harness for integration testing

## README

N/A — README updates are Phase 16 scope (issue #37). This issue adds test infrastructure only, no user-facing changes.
