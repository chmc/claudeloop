# OpenCode Adapter Implementation Plan (Issue #35)

## Context

**Issue:** https://github.com/chmc/claudeloop/issues/35 (Step 4: Phases 10-12)
**Parent:** https://github.com/chmc/claudeloop/issues/31 (Provider abstraction)

claudeloop's stream_processor.sh expects Claude stream-json format. OpenCode CLI emits different events. This plan implements:
- **Phase 10:** Event adapter (AWK normalizer)
- **Phase 11:** Permission adapter (HTTP protocol)
- **Phase 12:** Write-action and verdict detection patterns

The adapter-shim pattern preserves the 928-line stream processor unchanged.

## Files to Create/Modify

### Create

| File | Purpose |
|------|---------|
| `lib/adapters/opencode.sh` | OpenCode adapter: CLI args, event normalizer, detection patterns |
| `lib/adapters/permission_opencode.sh` | OpenCode permission adapter (HTTP protocol) |
| `tests/test_opencode_adapter.sh` | Unit and integration tests for adapter |
| `tests/fixtures/opencode_events/session_basic.ndjson` | Basic session fixture |
| `tests/fixtures/opencode_events/tool_error.ndjson` | Tool error fixture |
| `tests/fixtures/opencode_events/file_edited.ndjson` | File edit fixture |
| `tests/fixtures/opencode_events/permission_updated.ndjson` | Permission request fixture |
| `tests/fixtures/opencode_events/duplicate_pending.ndjson` | Same callID multiple times |
| `tests/fixtures/opencode_events/malformed_line.ndjson` | Invalid JSON mixed with valid |
| `tests/fixtures/opencode_events/session_idle.ndjson` | Session end/result fixture |

### Modify

| File | Change |
|------|--------|
| `lib/provider.sh` | Add opencode case, conditional sourcing, `provider_cli()` dispatch, `provider_normalize_events()` |
| `lib/permission_handler.sh` | Add provider switching for permission_filter() |
| `lib/execution.sh` | Insert `provider_normalize_events` in pipeline (~line 195) |
| `tests/test_provider.sh` | Update test at line 66-69 (expects opencode to fail → should pass) |

## Implementation Details

### Phase 10: Event Adapter (`lib/adapters/opencode.sh`)

**Event Mapping:**

| OpenCode Event | Claude Equivalent |
|----------------|-------------------|
| `message.part.updated` (text) | `assistant` |
| `message.part.updated` (tool pending/running) | `tool_use` |
| `message.part.updated` (tool completed/error) | `tool_result` |
| `file.edited` | `tool_use` (Edit) |
| `session.idle` | `result` |
| `session.created` (if exists) | `system` with `subtype: "init"` |

**Core Function: `_opencode_normalize_events()`**
- AWK-based filter that transforms OpenCode JSON to Claude stream-json
- Uses POSIX AWK (no gawk features) for portability
- Tracks tool state by callID to emit tool_use once, tool_result once
- Malformed JSON: emit to stderr with warning, do NOT pass to stdout (would corrupt log)
- Reuses `extract()` pattern from stream_processor.sh

**AWK State Tracking (skeleton):**
```awk
BEGIN {
  tool_id_counter = 0
  # tool_emitted[callID] = 1 when tool_use already emitted
  # tool_result_emitted[callID] = 1 when tool_result already emitted
}

# For each tool event:
if (!(call_id in tool_emitted)) {
  # emit tool_use
  tool_emitted[call_id] = 1
}
if (state == "completed" || state == "error") {
  if (!(call_id in tool_result_emitted)) {
    # emit tool_result
    tool_result_emitted[call_id] = 1
  }
}
```

**Adapter Functions (same interface as Claude):**
```sh
_opencode_cli()                  # Returns "opencode"
_opencode_exec_args()            # --format json --stream
_opencode_print_args()           # --format json
_opencode_write_tool_pattern()   # Edit|Write|NotebookEdit|Agent (post-normalization)
_opencode_verdict_pass_keyword() # VERIFICATION_PASSED
_opencode_verdict_fail_keyword() # VERIFICATION_FAILED
_opencode_permission_protocol()  # http
```

### Phase 11: Permission Adapter (`lib/adapters/permission_opencode.sh`)

**Protocol Difference:**
- Claude: FD7/FIFO bidirectional stdio (`_PERMISSION_FD` unused for OpenCode)
- OpenCode: HTTP POST to `/session/:id/permissions/:permissionID`

**Permission Event JSON Fields:**
```json
{
  "type": "permission.updated",
  "properties": {
    "id": "perm123",           // → :permissionID in URL
    "sessionID": "sess456",    // → :id in URL
    "type": "file.write",      // → tool_name for prompt
    "title": "Write to file"   // → reason for prompt
  }
}
```

**Response Mapping:**
| _permission_decide() | _permission_prompt_user() | OpenCode Response |
|---------------------|---------------------------|-------------------|
| allow | N/A | `{"response":"always"}` |
| interactive | returns "allow" | `{"response":"once"}` |
| interactive | returns "deny" | `{"response":"reject"}` |
| deny | N/A | `{"response":"reject"}` |

**Core Function: `_opencode_permission_filter()`**
- Intercepts `permission.updated` events (NOT passed downstream)
- Extracts `properties.id` → permissionID, `properties.sessionID` → sessionID
- Calls `_permission_decide()` from shared interface
- Sends HTTP POST via curl in background subshell (fire-and-forget)
- Logs warning on HTTP failure, does NOT block pipeline
- Passes all other events downstream unchanged

**Environment Variables:**
- `OPENCODE_HTTP_HOST` (default: localhost)
- `OPENCODE_HTTP_PORT` (default: 8080)
- `OPENCODE_SESSION_ID` (fallback if sessionID missing from events)

### Phase 12: Detection Patterns

**Write-Action Detection:**
After normalization, OpenCode events use Claude tool names. Pattern identical:
```sh
_opencode_write_tool_pattern() -> "Edit|Write|NotebookEdit|Agent"
```

**Verdict Keywords:**
Same as Claude for consistent prompt templates:
```sh
_opencode_verdict_pass_keyword() -> "VERIFICATION_PASSED"
_opencode_verdict_fail_keyword() -> "VERIFICATION_FAILED"
```

**Raw OpenCode Pattern (pre-normalization fallback):**
```sh
_opencode_raw_write_tool_pattern() -> "edit|write|file\.edit|file\.write|apply_patch"
```

## Provider Integration

### `lib/provider.sh` Changes

```sh
# Remove line 5: . "$SCRIPT_DIR/lib/adapters/claude.sh"
# Replace with conditional adapter sourcing at top of file:
case "${PROVIDER:-claude}" in
  claude)   . "$SCRIPT_DIR/lib/adapters/claude.sh" ;;
  opencode) . "$SCRIPT_DIR/lib/adapters/opencode.sh" ;;
  *)        . "$SCRIPT_DIR/lib/adapters/claude.sh" ;;
esac

# In provider_detect() (lines 10-22), add case:
opencode) printf 'opencode\n' ;;

# Modify provider_cli() (lines 25-27) to dispatch:
provider_cli() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_cli ;;
    *)        printf 'claude\n' ;;
  esac
}

# New function:
provider_normalize_events() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_normalize_events ;;
    *)        cat ;;  # Claude needs no normalization
  esac
}
```

### `lib/permission_handler.sh` Changes

```sh
# Replace lines 11-13 (unconditional Claude sourcing) with:
case "${PROVIDER:-claude}" in
  claude)   . "$SCRIPT_DIR/lib/adapters/permission_claude.sh" ;;
  opencode) . "$SCRIPT_DIR/lib/adapters/permission_opencode.sh" ;;
  *)        . "$SCRIPT_DIR/lib/adapters/permission_claude.sh" ;;
esac

# Note: _PERMISSION_FD only used by Claude adapter (stdio protocol)
# OpenCode adapter ignores it (HTTP protocol)

# permission_filter() routes to provider-specific implementation
```

### `lib/execution.sh` Changes

Insert normalizer in pipeline (~line 195):
```sh
# Before:
} | permission_filter | inject_heartbeats 7>&- | { process_stream_json ...

# After:
} | permission_filter | provider_normalize_events | inject_heartbeats 7>&- | { process_stream_json ...
```

## Test Strategy

### Contract Tests (`tests/test_opencode_adapter.sh`)

1. **Adapter Function Contracts:**
   - `_opencode_cli()` returns `opencode`
   - `_opencode_exec_args()` returns `--format json --stream`
   - `_opencode_print_args()` returns `--format json`
   - `_opencode_permission_protocol()` returns `http`
   - `_opencode_verdict_pass_keyword()` returns `VERIFICATION_PASSED`
   - `_opencode_verdict_fail_keyword()` returns `VERIFICATION_FAILED`
   - `_opencode_write_tool_pattern()` returns `Edit|Write|NotebookEdit|Agent`
   - `_opencode_raw_write_tool_pattern()` returns pre-normalization pattern

2. **Event Normalization:**
   - `message.part.updated` (text) → `assistant` event
   - `message.part.updated` (tool pending) → `tool_use` (emitted once)
   - `message.part.updated` (tool running) → no new output (state tracked)
   - `message.part.updated` (tool completed) → `tool_result`
   - `message.part.updated` (tool error) → `tool_result` with `is_error: true`
   - `file.edited` → `tool_use` (Edit)
   - `session.idle` → `result` event
   - Duplicate callID pending events → single `tool_use`
   - Malformed JSON → stderr warning, NOT passed to stdout

3. **Permission Filter:**
   - Non-permission events pass through unchanged
   - `permission.updated` events intercepted (not downstream)
   - HTTP POST sent with correct body (mock curl)
   - HTTP failure logs warning, does NOT block pipeline
   - Response mapping: allow→always, yes→once, no→reject, deny→reject

4. **Integration Tests:**
   - `PROVIDER=opencode` loads correct adapter
   - `provider_normalize_events()` returns cat for claude, normalizer for opencode
   - Normalized events flow through `process_stream_json` correctly

### Fixture Files

```
tests/fixtures/opencode_events/
├── session_basic.ndjson       # Happy path: text + tool + result
├── tool_error.ndjson          # Tool failure with error message
├── file_edited.ndjson         # file.edited event
├── permission_updated.ndjson  # Permission request event
├── duplicate_pending.ndjson   # Same callID multiple pending events
├── malformed_line.ndjson      # Invalid JSON mixed with valid
└── session_idle.ndjson        # Session end event
```

## Verification Checklist

### Contract Tests
- [ ] `_opencode_cli()` returns `opencode`
- [ ] `_opencode_exec_args()` returns `--format json --stream`
- [ ] `_opencode_print_args()` returns `--format json`
- [ ] `_opencode_permission_protocol()` returns `http`
- [ ] `_opencode_verdict_pass_keyword()` returns `VERIFICATION_PASSED`
- [ ] `_opencode_verdict_fail_keyword()` returns `VERIFICATION_FAILED`
- [ ] `_opencode_write_tool_pattern()` returns `Edit|Write|NotebookEdit|Agent`

### Event Normalization
- [ ] text → assistant
- [ ] tool pending → tool_use (once per callID)
- [ ] tool completed → tool_result
- [ ] tool error → tool_result with is_error
- [ ] file.edited → Edit tool_use
- [ ] session.idle → result
- [ ] Malformed JSON → stderr only

### Permission Filter
- [ ] Non-permission events pass through
- [ ] permission.updated intercepted
- [ ] HTTP POST correct format
- [ ] HTTP failure does not block

### Integration
- [ ] `PROVIDER=opencode` sources opencode.sh
- [ ] Normalized events work with stream_processor

### Regression
- [ ] `bats tests/test_provider.sh` passes (update line 66-69 test)
- [ ] `bats tests/test_permission_handler.sh` passes
- [ ] `./tests/smoke.sh` passes (Claude path unchanged)

## Implementation Sequence

1. **Create `lib/adapters/opencode.sh`** with:
   - `_opencode_cli()` returning "opencode"
   - CLI arg functions (`_opencode_exec_args`, `_opencode_print_args`)
   - `_opencode_normalize_events()` AWK filter with state tracking
   - Detection pattern functions

2. **Create `lib/adapters/permission_opencode.sh`** with:
   - Field extraction helper (`_opencode_extract_field`)
   - HTTP response function (`_opencode_send_permission_response`)
   - `_opencode_permission_filter()` pipeline stage

3. **Modify `lib/provider.sh`**:
   - Remove unconditional Claude sourcing (line 5)
   - Add conditional adapter sourcing at top
   - Add opencode case to `provider_detect()`
   - Modify `provider_cli()` to dispatch based on provider
   - Add `provider_normalize_events()` function

4. **Modify `lib/permission_handler.sh`**:
   - Replace unconditional Claude sourcing with provider switch
   - Route `permission_filter()` to provider implementation

5. **Modify `lib/execution.sh`**:
   - Insert `provider_normalize_events` in pipeline (~line 195)

6. **Update `tests/test_provider.sh`**:
   - Modify test at lines 66-69 (expects opencode to fail → should pass)

7. **Create test fixtures**:
   - `tests/fixtures/opencode_events/*.ndjson` (7 fixture files)

8. **Create `tests/test_opencode_adapter.sh`**:
   - Contract tests for all adapter functions
   - Event normalization tests
   - State tracking tests
   - Permission filter tests
   - Integration tests

9. **Run verification**:
   - `bats tests/test_opencode_adapter.sh`
   - `bats tests/test_provider.sh`
   - `bats tests/test_permission_handler.sh`
   - `./tests/smoke.sh`

## Dependencies

- curl (for HTTP permission responses)
- POSIX AWK (gawk/mawk/busybox awk)

## Risks

| Risk | Mitigation |
|------|------------|
| OpenCode event format differs from documented | Version-check CLI, add fixtures for actual output |
| AWK portability issues | Test with gawk, mawk, busybox awk |
| HTTP POST failures | Fire-and-forget with warning log, don't block pipeline |
| Tool state edge cases | Comprehensive state machine tests |

## Out of Scope

- Wiring OpenCode to execution pipeline (Phase 13)
- fake_opencode test harness (Phase 14)
- Packaging updates (Phase 15)
- Full documentation (Phase 16)

These are covered by subsequent issues (#36, #37).

## Architecture Impact

**Minimal impact by design.** The adapter-shim pattern adds:
- 2 new files in `lib/adapters/` (opencode.sh, permission_opencode.sh)
- Conditional sourcing in `lib/provider.sh` and `lib/permission_handler.sh`
- One pipeline stage insertion in `lib/execution.sh`

**No changes to:**
- `lib/stream_processor.sh` (928-line AWK parser unchanged)
- Core orchestration logic (`main_loop`, retry strategy)
- PROGRESS.md schema or sidecar file formats
- Exit code contract (0/1/2)

**Existing patterns preserved:**
- Provider interface contract (8 functions)
- Permission interface (shared `_permission_decide()`)
- Test patterns (bats, fixtures)

## ADR

Reference existing: `docs/adr/0037-provider-abstraction.md` (accepted)

No new ADR needed - this implements Phases 10-12 of the accepted architecture. The adapter-shim pattern and event normalization approach were decided in ADR-0037.

## Workflow / State Machines

**Event Normalizer State Machine:**
```
                    ┌──────────────┐
   tool event ──────►  callID new? │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │ yes                     │ no
              ▼                         ▼
   ┌──────────────────┐        ┌───────────────┐
   │ emit tool_use    │        │ check state   │
   │ mark emitted[id] │        └───────┬───────┘
   └──────────────────┘                │
                           ┌───────────┴───────────┐
                           │ completed/error       │ pending/running
                           ▼                       ▼
                  ┌─────────────────┐      ┌──────────────┐
                  │ emit tool_result│      │ no output    │
                  │ mark result[id] │      │ (state only) │
                  └─────────────────┘      └──────────────┘
```

**Permission Filter Flow:**
```
event received
      │
      ▼
is permission.updated? ──yes──► extract sessionID, permissionID
      │                                    │
      │ no                                 ▼
      ▼                          call _permission_decide()
pass downstream                            │
                               ┌───────────┴───────────┐
                               │                       │
                          allow/deny            interactive
                               │                       │
                               ▼                       ▼
                      HTTP POST (bg)        prompt user → HTTP POST (bg)
```

## Tests

**New test file:** `tests/test_opencode_adapter.sh`
- 8+ contract tests (one per adapter function)
- 9+ normalization tests (one per event type + edge cases)
- 5+ permission filter tests
- 3+ integration tests

**Fixture files:** 7 new files in `tests/fixtures/opencode_events/`

**Modified test:** `tests/test_provider.sh` line 66-69 (expects opencode to pass)

**Test commands:**
```sh
bats tests/test_opencode_adapter.sh
bats tests/test_provider.sh
bats tests/test_permission_handler.sh
./tests/smoke.sh
```

## Documentation

**No user-facing docs in this phase.** OpenCode support is not wired end-to-end until Phase 13.

Documentation updates planned for Phase 16 (issue #37):
- README.md multi-provider section
- QUICKSTART.md `--provider` flag
- Provider capabilities matrix

## Install / Uninstall

**No changes to install.sh in this phase.** New lib files will be added in Phase 15 (issue #37).

Current install.sh does not need modification because:
- New files are in `lib/adapters/` (already covered by install pattern)
- No new binaries or dependencies

## Release

**No release in this phase.** This implements Phases 10-12 only.

Release will occur after Phase 16 completes (full issue #37):
- `/release beta` after all phases verified
- Changelog entry: "Add OpenCode provider adapter (preview)"

## README

N/A - No README changes in this phase. README updates are planned for Phase 16 (issue #37) when OpenCode support is fully wired and documented.
