# Plan: GitHub Issue #33 - Abstract Detection Helpers (Phases 5-7)

## Context

**Issue:** [chmc/claudeloop#33](https://github.com/chmc/claudeloop/issues/33) - Step 2 of provider abstraction  
**Parent:** [#31](https://github.com/chmc/claudeloop/issues/31) - Decouple claudeloop from Claude CLI  
**Status:** Phases 1-4 COMPLETE (provider scaffolding exists)

**Why this change:** claudeloop currently hardcodes Claude-specific tool names, verdict keywords, and permission protocols. This blocks support for other AI CLIs (OpenCode) and makes protocol changes risky. Phases 5-7 abstract these detection helpers behind the provider interface.

**Current state:**
- `lib/provider.sh` exists with `provider_detect()`, `provider_cli()`, `provider_exec_args()`, `provider_print_args()`
- `lib/adapters/claude.sh` implements Claude-specific CLI flags
- All execution paths already use provider abstraction for CLI invocation

---

## Analysis Summary

### Phase 5: Write-Action Detection
**Current:** `lib/retry.sh:148-157` has hardcoded AWK patterns:
```awk
/"name":"Edit"/ || /"name":"Write"/ || /"name":"NotebookEdit"/ {found=1}
/"name":"Agent"/ {found=1}
```
**Callers:** `lib/execution.sh` (5 call sites for safety gates)

### Phase 6: Verdict Keywords
**Current:** Hardcoded `VERIFICATION_PASSED`/`VERIFICATION_FAILED` in:
- `lib/verify.sh:74-75,216,228` (prompt + check)
- `lib/refactor.sh:100-101` (prompt)
- `lib/retry.sh:421,431` (error extraction)
- `lib/plan_changes.sh:472` (result parsing)
- `lib/recorder_parsers.sh:477,479` (replay parsing)

### Phase 7: Permission Interface
**Current:** `lib/permission_handler.sh` (141 lines) - Claude's bidirectional FD7/FIFO `control_request`/`control_response` protocol

---

## Design Decision: Full Abstraction Required

Initial minimalism review suggested simplifying Phase 7. However, **OpenCode research reveals it has a full bidirectional permission protocol** (via HTTP endpoints + SSE events), not just CLI flags.

| Concern | Implementation | Rationale |
|---------|----------------|-----------|
| Write tools | `provider_write_tool_pattern()` | OpenCode uses different tool names |
| Verdict keywords | `provider_verdict_pass/fail_keyword()` | 6+ files use them; central source of truth |
| Permission | 2 new files + facade refactor | Both providers have bidirectional protocols (stdio vs HTTP) |

---

## Implementation Plan

### Phase 5: Abstract Write-Action Detection

**Files to modify:**

1. **`lib/adapters/claude.sh`** - Add:
   ```sh
   _claude_write_tool_pattern() {
     printf '%s' 'Edit|Write|NotebookEdit|Agent'
   }
   ```

2. **`lib/provider.sh`** - Add:
   ```sh
   provider_write_tool_pattern() {
     _claude_write_tool_pattern
   }
   ```

3. **`lib/retry.sh:148-157`** - Modify `has_write_actions()`:
   ```sh
   has_write_actions() {
     local raw_log="$1"
     [ -f "$raw_log" ] || return 1
     local _tools
     _tools=$(provider_write_tool_pattern)  # Returns: Edit|Write|NotebookEdit|Agent
     awk -v tools="$_tools" '
       BEGIN { n = split(tools, t, "|") }
       /^=== EXECUTION START /{found=0; next}
       {
         for (i = 1; i <= n; i++) {
           if (index($0, "\"name\":\"" t[i] "\"") > 0) { found=1; break }
         }
       }
       END{exit (found ? 0 : 1)}
     ' "$raw_log"
   }
   ```
   
   **Note:** Uses POSIX AWK `index()` function (not gawk-specific `match()` with array capture).

4. **`tests/test_provider.sh`** - Add:
   ```sh
   @test "provider_write_tool_pattern: returns pipe-separated tool names" {
     run provider_write_tool_pattern
     [ "$status" -eq 0 ]
     [ "$output" = "Edit|Write|NotebookEdit|Agent" ]
   }
   ```

**Verification:**
- [ ] All 9 existing `has_write_actions` tests pass
- [ ] New provider test passes
- [ ] Smoke test: full pipeline works

---

### Phase 6: Abstract Verdict Keywords

**Files to modify:**

1. **`lib/adapters/claude.sh`** - Add:
   ```sh
   _claude_verdict_pass_keyword() {
     printf '%s' 'VERIFICATION_PASSED'
   }
   
   _claude_verdict_fail_keyword() {
     printf '%s' 'VERIFICATION_FAILED'
   }
   ```

2. **`lib/provider.sh`** - Add:
   ```sh
   provider_verdict_pass_keyword() {
     _claude_verdict_pass_keyword
   }
   
   provider_verdict_fail_keyword() {
     _claude_verdict_fail_keyword
   }
   ```

3. **`lib/verify.sh`** - Modify:
   - Lines 74-75: Use variables in prompt
   - Lines 216, 228: Use provider functions in `check_verdict()`

4. **`lib/refactor.sh:100-101`** - Use provider functions in prompt

5. **`lib/retry.sh:431`** - Use `provider_verdict_fail_keyword()` in `extract_verify_error()`

6. **`lib/plan_changes.sh:472`** - Use provider function

7. **`lib/recorder_parsers.sh:477,479`** - Use provider functions

8. **`tests/test_provider.sh`** - Add keyword tests

**Verification:**
- [ ] All existing verify tests pass
- [ ] Verdict detection works for PASSED
- [ ] Verdict detection works for FAILED
- [ ] Anti-skip check still works

---

### Phase 7: Abstract Permission Interface (Full Abstraction)

**Research finding:** OpenCode has a **full bidirectional permission protocol**, not just CLI flags:
- **Event:** `EventPermissionUpdated` (SSE/JSON stream)
- **Response:** `POST /session/:id/permissions/:permissionID` or event reply
- **Format:** `{ response: "once"/"always"/"reject" }` (vs Claude's `"allow"/"deny"`)

Both Claude and OpenCode need protocol adapters. The issue's 3-file approach is correct.

**Files to create:**

1. **`lib/permission_interface.sh`** (NEW) - Shared decision logic:
   ```sh
   #!/bin/sh
   # Permission Interface - Provider-agnostic decision logic
   
   # Decide permission action based on config and environment
   # Returns: "allow", "deny", or "interactive" (stdout)
   _permission_decide() {
     if [ "$SKIP_PERMISSIONS" = "true" ]; then
       printf 'allow\n'
       return
     fi
     if [ -t 0 ] 2>/dev/null || [ -e /dev/tty ]; then
       printf 'interactive\n'
       return
     fi
     printf 'deny\n'
   }
   
   # Prompt user for permission via TTY (provider-agnostic)
   # Args: $1 - tool name, $2 - reason
   # Returns: "allow" or "deny"
   _permission_prompt_user() {
     local _tool_name="$1" _reason="${2:-Permission requested}"
     {
       printf '[%s] Permission requested: %s\n' "$(date '+%H:%M:%S')" "$_tool_name"
       printf '  Reason: %s\n' "$_reason"
       printf '  Allow? (y/n): '
     } > /dev/tty 2>/dev/null || true
     local _answer=""
     read -r _answer < /dev/tty 2>/dev/null || _answer="n"
     case "$_answer" in
       [Yy]|[Yy][Ee][Ss]) printf 'allow\n' ;;
       *) printf 'deny\n' ;;
     esac
   }
   ```

2. **`lib/adapters/permission_claude.sh`** (NEW) - Claude FD7/FIFO protocol:
   ```sh
   #!/bin/sh
   # Claude Permission Adapter - FD7/FIFO bidirectional protocol
   
   . "$SCRIPT_DIR/lib/permission_interface.sh"
   
   # Move current _extract_field, _build_allow_response, _build_deny_response,
   # _handle_control_request, permission_filter here with _claude_ prefix
   
   _claude_permission_filter() {
     # Current permission_filter() implementation
   }
   ```

3. **`lib/permission_handler.sh`** (MODIFY) - Facade loading adapter:
   ```sh
   #!/bin/sh
   # Permission Handler - Facade
   # Loads provider-specific permission adapter
   
   . "$SCRIPT_DIR/lib/adapters/permission_claude.sh"
   
   # Public API - backward compatible
   _extract_field() { _claude_extract_field "$@"; }
   _build_stream_message() { _claude_build_stream_message "$@"; }
   _build_allow_response() { _claude_build_allow_response "$@"; }
   _build_deny_response() { _claude_build_deny_response "$@"; }
   permission_filter() { _claude_permission_filter; }
   ```

**Files to modify:**

4. **`lib/provider.sh`** - Add permission mode function:
   ```sh
   # Returns permission protocol: "stdio" (Claude FD7), "http" (OpenCode API), "none"
   provider_permission_protocol() {
     _claude_permission_protocol
   }
   ```

5. **`lib/adapters/claude.sh`** - Add:
   ```sh
   _claude_permission_protocol() {
     printf '%s' 'stdio'
   }
   ```

6. **`tests/test_permission_handler.sh`** - Add interface tests:
   ```sh
   @test "_permission_decide: returns allow when SKIP_PERMISSIONS=true" { ... }
   @test "_permission_decide: returns deny when no TTY" { ... }
   ```

**Why full abstraction is needed:**

| Aspect | Claude | OpenCode |
|--------|--------|----------|
| Transport | FD7/FIFO (stdio) | HTTP endpoint |
| Request event | `control_request` | `EventPermissionUpdated` |
| Response event | `control_response` | HTTP POST body |
| Allow format | `{ behavior: "allow" }` | `{ response: "once" }` |
| Deny format | `{ behavior: "deny" }` | `{ response: "reject" }` |
| Remember | N/A | `{ response: "always" }` |

**Verification:**
- [ ] All existing permission tests pass
- [ ] Auto-allow mode works (SKIP_PERMISSIONS=true)
- [ ] Interactive mode works (TTY present)
- [ ] Auto-deny mode works (no TTY)
- [ ] Facade preserves backward compatibility

---

## File Summary

### Files Created
| File | Phase | Purpose |
|------|-------|---------|
| `lib/permission_interface.sh` | 7 | Shared decision logic (`_permission_decide`, `_permission_prompt_user`) |
| `lib/adapters/permission_claude.sh` | 7 | Claude FD7/FIFO protocol implementation |

### Files Modified
| File | Phase | Changes |
|------|-------|---------|
| `lib/provider.sh` | 5,6,7 | Add 5 new functions (pattern, keywords, protocol) |
| `lib/adapters/claude.sh` | 5,6,7 | Add 5 adapter functions |
| `lib/retry.sh` | 5,6 | `has_write_actions()`, `extract_verify_error()` |
| `lib/verify.sh` | 6 | `check_verdict()`, prompt |
| `lib/refactor.sh` | 6 | Prompt keywords |
| `lib/plan_changes.sh` | 6 | Verdict parsing |
| `lib/recorder_parsers.sh` | 6 | Verdict parsing |
| `lib/permission_handler.sh` | 7 | Refactor to facade loading adapter |
| `tests/test_provider.sh` | 5,6,7 | Add contract tests |
| `tests/test_permission_handler.sh` | 7 | Add interface tests |

---

## Testing Strategy

1. **Existing tests must pass** after each phase
2. **Add adapter contract tests** to `test_provider.sh`:
   - Pattern validity tests
   - Keyword return value tests
   - Permission mode tests
3. **Run full test suite** before marking phase complete

---

## Implementation Order

1. **Phase 5** first (write-action) - isolated, easy to test
2. **Phase 6** second (verdict keywords) - more touch points but straightforward
3. **Phase 7** last (permission) - most complex, benefits from earlier patterns

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| AWK regex compatibility across implementations | Test with gawk, mawk, busybox awk |
| Many files touch verdict keywords | Central functions = single source of truth |
| Permission refactor breaks pipeline | Facade preserves all public function names |
| Permission adapter sourcing order | Ensure SCRIPT_DIR set before sourcing |
| FD7 conflicts in tests | Existing subshell pattern handles this |

---

## Verification Checklist (End of Implementation)

**Phase 5:**
- [ ] `has_write_actions()` detects Edit, Write, NotebookEdit, Agent
- [ ] `has_write_actions()` ignores Read, Glob, Grep, Bash
- [ ] `provider_write_tool_pattern()` returns correct pattern

**Phase 6:**
- [ ] Verdict detection works for PASSED
- [ ] Verdict detection works for FAILED
- [ ] Anti-skip check (`tool_use` required) still works
- [ ] `provider_verdict_pass/fail_keyword()` return correct strings

**Phase 7:**
- [ ] Auto-allow mode works (SKIP_PERMISSIONS=true)
- [ ] Auto-deny mode works (no TTY, no SKIP_PERMISSIONS)
- [ ] Interactive mode works (TTY present)
- [ ] Facade preserves all public function names
- [ ] `_permission_decide()` returns correct modes

**Overall:**
- [ ] All existing tests pass
- [ ] Smoke test passes
- [ ] `/verify` passes
