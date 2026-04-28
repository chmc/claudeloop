# Implementation Plan: Provider Scaffolding (Issue #32, Phases 1-4)

## Context

**Problem**: claudeloop hardcodes Claude CLI binary and flags in multiple locations, blocking multi-provider support (OpenCode, etc.).

**Goal**: Create provider abstraction layer and extract Claude invocations to adapter pattern. **No behavior change** - refactor only. All existing tests must pass after each phase.

**Parent issue**: #31 defines full 16-phase provider abstraction. This plan covers Steps 1 (Phases 1-4) only.

## Constraints Brief

### Touch Points (Claude CLI invocations)

| Location | Function | Current Command |
|----------|----------|-----------------|
| `claudeloop:577-581` | `validate_environment()` | `command -v claude` |
| `lib/ai_parser.sh:38` | `run_claude_print()` | `claude --print --output-format=stream-json --verbose --include-partial-messages` |
| `lib/execution.sh:117-119` | `run_claude_pipeline()` | `claude --input-format stream-json --output-format stream-json --permission-prompt-tool stdio --verbose --include-partial-messages $_claude_debug_flag` |
| `lib/verify.sh:115-116` | `verify_phase()` | Same as execution (no debug flag) |

### Invariants (MUST preserve)

1. `unset CLAUDECODE` before invocation (ai_parser.sh:28, execution.sh:115)
2. FD 7 for bidirectional permission protocol (execution.sh, verify.sh)
3. Exit code captured to temp file (`$_exit_tmp`)
4. Pipeline order: `claude | permission_filter | inject_heartbeats | process_stream_json`
5. Exact flag strings and order preserved

### Conventions

- POSIX `#!/bin/sh`, no bashisms
- Public functions: `verb_noun()`, private: `_underscore_prefix()`
- Use `printf` not `echo`
- Files sourced, not executed

## Implementation

### Phase 1: Provider Interface Scaffolding

**Goal**: Create files with stub functions. No behavior change.

**Create `lib/provider.sh`** (~40 lines):
```sh
#!/bin/sh
# Provider abstraction layer

SCRIPT_DIR_PROVIDER="${SCRIPT_DIR_PROVIDER:-$(cd "$(dirname "$0")" && pwd)}"

# Source active adapter
. "$SCRIPT_DIR_PROVIDER/adapters/claude.sh"

# Detection - returns provider name
provider_detect() {
  printf 'claude\n'
}

# Return CLI binary name
provider_cli() {
  printf 'claude\n'
}

# Return execution mode flags (stream-json pipeline)
provider_exec_args() {
  _claude_exec_args
}

# Return print mode flags (AI parse)
provider_print_args() {
  _claude_print_args
}
```

**Create `lib/adapters/` directory and `lib/adapters/claude.sh`** (~25 lines):
```sh
#!/bin/sh
# Claude CLI adapter

_claude_exec_args() {
  printf '%s' '--input-format stream-json --output-format stream-json --permission-prompt-tool stdio --verbose --include-partial-messages'
}

_claude_print_args() {
  printf '%s' '--print --output-format=stream-json --verbose --include-partial-messages'
}
```

**Create `tests/test_provider.sh`** (~50 lines):
```sh
#!/usr/bin/env bash
# bats file_tags=provider

setup() {
  SCRIPT_DIR_PROVIDER="${BATS_TEST_DIRNAME}/.."
  . "${BATS_TEST_DIRNAME}/../lib/provider.sh"
}

@test "provider_detect: returns claude" {
  run provider_detect
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "provider_cli: returns claude" {
  run provider_cli
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "provider_exec_args: returns exact execution flags" {
  run provider_exec_args
  [ "$status" -eq 0 ]
  [ "$output" = "--input-format stream-json --output-format stream-json --permission-prompt-tool stdio --verbose --include-partial-messages" ]
}

@test "provider_print_args: returns exact print flags" {
  run provider_print_args
  [ "$status" -eq 0 ]
  [ "$output" = "--print --output-format=stream-json --verbose --include-partial-messages" ]
}
```

**Files**:
- `lib/provider.sh` (NEW)
- `lib/adapters/claude.sh` (NEW)
- `tests/test_provider.sh` (NEW)

**Verification**: `bats tests/test_provider.sh` passes

---

### Phase 2: Wire Provider Detection in Main Script

**Goal**: Source provider lib, call `provider_detect()` at startup.

**Modify `claudeloop`**:

1. Add source after line 47 (after execution.sh):
```sh
. "$SCRIPT_DIR/lib/provider.sh"
```

2. Modify `validate_environment()` (lines 577-581):
```sh
  # Detect provider
  _provider=$(provider_detect)
  log_verbose "Provider: $_provider"

  # Check if provider CLI is available
  if ! command -v "$(provider_cli)" > /dev/null 2>&1; then
    print_error "$(provider_cli) CLI not found. Please install it first."
    exit 1
  fi
```

**Files**: `claudeloop` (MODIFY ~10 lines)

**Verification**:
- `./claudeloop --help` unchanged
- `./claudeloop -v --dry-run --plan PLAN.md` shows "Provider: claude"
- All existing tests pass

---

### Phase 3: Extract Claude Invocation to Adapter

**Goal**: Replace hardcoded flags with provider functions.

**Modify `lib/execution.sh`** (lines 117-119):
```sh
# Before:
claude --input-format stream-json --output-format stream-json \
  --permission-prompt-tool stdio --verbose --include-partial-messages \
  $_claude_debug_flag \

# After:
# shellcheck disable=SC2046
$(provider_cli) $(provider_exec_args) \
  $_claude_debug_flag \
```

**Modify `lib/ai_parser.sh`** (line 38):
```sh
# Before:
claude --print --output-format=stream-json --verbose --include-partial-messages \

# After:
# shellcheck disable=SC2046
$(provider_cli) $(provider_print_args) \
```

**Files**:
- `lib/execution.sh` (MODIFY ~2 lines)
- `lib/ai_parser.sh` (MODIFY ~2 lines)

**Verification**:
- Smoke test: full pipeline works
- AI parse works unchanged
- All existing tests pass

---

### Phase 4: Extract Verify Invocation to Adapter

**Goal**: Apply same pattern to verify.sh.

**Modify `lib/verify.sh`** (lines 115-116):
```sh
# Before:
claude --input-format stream-json --output-format stream-json \
  --permission-prompt-tool stdio --verbose --include-partial-messages \

# After:
# shellcheck disable=SC2046
$(provider_cli) $(provider_exec_args) \
```

**Files**: `lib/verify.sh` (MODIFY ~2 lines)

**Verification**:
- Verification pass test
- Verification fail test
- Full pipeline with `--verify` enabled

---

## Critical Files Summary

| File | Action | Lines |
|------|--------|-------|
| `lib/provider.sh` | NEW | ~40 |
| `lib/adapters/claude.sh` | NEW | ~25 |
| `tests/test_provider.sh` | NEW | ~50 |
| `claudeloop` | MODIFY | lines 48, 577-581 |
| `lib/execution.sh` | MODIFY | lines 117-119 |
| `lib/ai_parser.sh` | MODIFY | line 38 |
| `lib/verify.sh` | MODIFY | lines 115-116 |

## Verification Checklist

After each phase:
- [ ] `bats tests/` - all existing tests pass
- [ ] `./claudeloop --help` - unchanged output  
- [ ] `shellcheck lib/provider.sh lib/adapters/claude.sh`
- [ ] Smoke test with real Claude CLI (if available)

Final verification:
- [ ] `./tests/run_all_tests.sh` - full suite passes
- [ ] `./claudeloop --plan PLAN.md --dry-run` - works
- [ ] Verbose mode shows "Provider: claude"

## Deferred to Later Phases

Per issue #31, explicitly **NOT in scope** for Phases 1-4:
- `provider_write_tool_pattern()` - Phase 5
- `provider_verdict_pass_keyword()` - Phase 6
- Permission adapter abstraction - Phase 7
- `--provider` CLI flag - Phase 8
- OpenCode adapter - Phases 10-14

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Flag string mismatch | Exact string comparison in tests |
| Word splitting issues | `shellcheck disable=SC2046` comment, no spaces in flags |
| Sourcing order | Add provider.sh after execution.sh in source chain |
| FD 7 breakage | Don't touch FIFO/FD setup, only CLI invocation line |
