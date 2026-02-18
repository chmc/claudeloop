# Killswitch Feature

The killswitch allows you to **immediately stop execution** at any time by pressing **Ctrl+C**, with full state preservation and resume capability.

## How It Works

### Architecture

```
User presses Ctrl+C
      ↓
SIGINT signal caught
      ↓
handle_interrupt() called
      ↓
┌─────────────────────────────────┐
│ 1. Mark in-progress phase      │
│    as "pending"                 │
│                                 │
│ 2. Decrement attempt counter    │
│    (don't count as failed)      │
│                                 │
│ 3. Save PROGRESS.md             │
│                                 │
│ 4. Save state file              │
│    (.claudeloop/state/          │
│     current.json)               │
│                                 │
│ 5. Remove lock file             │
│                                 │
│ 6. Exit cleanly (code 130)      │
└─────────────────────────────────┘
```

### State Preservation

When interrupted, ClaudeLoop saves:

1. **PROGRESS.md** - Full phase status
   ```markdown
   ### ✅ Phase 1: Setup
   Status: completed

   ### ⏳ Phase 2: Implementation
   Status: pending
   Attempts: 0

   ### ⏳ Phase 3: Tests
   Status: pending
   ```

2. **State File** (`.claudeloop/state/current.json`)
   ```json
   {
     "plan_file": "PLAN.md",
     "progress_file": "PROGRESS.md",
     "current_phase": "2",
     "interrupted": true,
     "timestamp": "2026-02-18T15:30:00Z"
   }
   ```

3. **Lock File Cleanup** - Removes `.claudeloop/lock` to allow resume

## Usage Example

### Scenario: Interrupting During Phase 2

```bash
$ ./claudeloop
═══════════════════════════════════════════════════════════
ClaudeLoop - Phase-by-Phase Execution
═══════════════════════════════════════════════════════════
Plan: PLAN.md
Progress: 1/3 phases completed
═══════════════════════════════════════════════════════════

✓ Parsing plan file: PLAN.md
Found 3 phases

✅ Phase 1: Setup
🔄 Phase 2: Implementation
⏳ Phase 3: Tests

⚠ Press Ctrl+C at any time to stop (state will be saved)

───────────────────────────────────────────────────────────
▶ Executing Phase 2: Implementation
───────────────────────────────────────────────────────────

Executing Claude CLI...
> Reading existing code...
> Implementing feature...

[User presses Ctrl+C]

^C
⚠ Interrupt received (Ctrl+C)
⚠ Saving state and shutting down gracefully...
⚠ Marking Phase 2 as pending for retry

✓ State saved successfully
✓ Resume with: ./claudeloop --continue
```

### Resuming Execution

```bash
$ ./claudeloop --continue

# Or just:
$ ./claudeloop

═══════════════════════════════════════════════════════════
ClaudeLoop - Phase-by-Phase Execution
═══════════════════════════════════════════════════════════
Plan: PLAN.md
Progress: 1/3 phases completed
═══════════════════════════════════════════════════════════

✓ Parsing plan file: PLAN.md
Found 3 phases

⚠ Found interrupted session
Resume from last checkpoint? (Y/n) y

✅ Phase 1: Setup
⏳ Phase 2: Implementation
⏳ Phase 3: Tests

⚠ Press Ctrl+C at any time to stop (state will be saved)

───────────────────────────────────────────────────────────
▶ Executing Phase 2: Implementation
───────────────────────────────────────────────────────────

... continues from Phase 2
```

## Implementation Details

### Signal Handlers

```bash
# Set up in main()
trap handle_interrupt SIGINT SIGTERM
trap cleanup EXIT
```

### Interrupt Handler

```bash
handle_interrupt() {
  INTERRUPTED=true

  # Mark current phase as pending (not failed)
  if [ -n "$CURRENT_PHASE" ]; then
    PHASE_STATUS[$CURRENT_PHASE]="pending"
    # Don't count this as an attempt
    PHASE_ATTEMPTS[$CURRENT_PHASE]=$((${PHASE_ATTEMPTS[$CURRENT_PHASE]} - 1))
  fi

  # Save progress
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  # Save state
  save_state

  # Cleanup
  remove_lock

  exit 130
}
```

### State Management

```bash
# Save state
save_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" << EOF
{
  "plan_file": "$PLAN_FILE",
  "progress_file": "$PROGRESS_FILE",
  "current_phase": "$CURRENT_PHASE",
  "interrupted": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Load state
load_state() {
  if [ -f "$STATE_FILE" ]; then
    if grep -q '"interrupted": true' "$STATE_FILE"; then
      # Prompt user to resume
      return 0
    fi
  fi
  return 1
}
```

### Lock File

```bash
# Create lock with PID
create_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local pid=$(cat "$LOCK_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      # Another instance is running
      exit 1
    fi
  fi
  echo $$ > "$LOCK_FILE"
}

# Remove lock
remove_lock() {
  rm -f "$LOCK_FILE"
}
```

## Benefits

1. **No Work Lost** - All progress is preserved
2. **Safe Interruption** - Clean shutdown, no corruption
3. **Flexible Workflow** - Stop and resume at will
4. **Concurrent Protection** - Lock file prevents conflicts
5. **Transparent** - Clear messages about what's happening

## Testing

See `tests/test_killswitch.sh` for test coverage:

```bash
✓ killswitch: handle_interrupt function saves state
✓ killswitch: state file is created with correct format
✓ killswitch: progress reading restores phase status
✓ killswitch: lock file prevents concurrent runs
```

## Use Cases

### 1. Need to Stop for a Break
```bash
# Working on long project
./claudeloop
# Break time - Ctrl+C
# Resume later
./claudeloop
```

### 2. Want to Review Progress
```bash
./claudeloop
# Ctrl+C after Phase 2
# Review Phase 2 changes
git log -1
git diff HEAD~1
# Continue
./claudeloop
```

### 3. Need to Modify Plan
```bash
./claudeloop
# Ctrl+C
# Edit PLAN.md to adjust remaining phases
vim PLAN.md
# Continue with updated plan
./claudeloop
```

### 4. System Maintenance
```bash
./claudeloop
# System update required - Ctrl+C
# After reboot
cd project
./claudeloop  # Picks up where it left off
```

## Edge Cases Handled

- ✅ Multiple Ctrl+C presses (exits immediately)
- ✅ Interrupt during Claude CLI execution (output saved)
- ✅ Interrupt between phases (state preserved)
- ✅ Lock file removal on crash (stale lock detection)
- ✅ Concurrent run attempts (PID-based lock)

## Future Enhancements

- [ ] Save partial Claude output on interrupt
- [ ] Auto-save state periodically (not just on interrupt)
- [ ] Interrupt timeout (force kill after N seconds)
- [ ] Resume with specific phase override
- [ ] State file encryption for sensitive plans
