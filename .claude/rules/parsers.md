---
paths:
  - "lib/progress.sh"
  - "lib/plan_changes.sh"
  - "lib/recorder.sh"
  - "lib/recorder_parsers.sh"
  - "lib/recorder_overview.sh"
---

# Three-Parser Invariant

PROGRESS.md is parsed by **three independent implementations** that must stay in sync:

| Parser | Location | Namespace |
|--------|----------|-----------|
| `read_progress()` | `lib/progress.sh` | `phase_get`/`phase_set` (via `lib/phase_state.sh`) |
| `read_old_phase_list()` | `lib/plan_changes.sh` | `old_phase_get`/`old_phase_set` |
| `rec_load_progress()` | `lib/recorder.sh` | raw `eval _REC_PHASE_*` (independent impl) |

The recorder uses its own eval namespace — it does **not** share the `phase_state.sh` abstraction. Manual sync required.

## Checklist for adding/removing a PROGRESS.md field

1. **Write site** — where the field is written to PROGRESS.md
2. **All three read sites** — update all three parsers above
3. **Transfer list** — if per-attempt field: add to `transfer_attempt_fields()` in `lib/plan_changes.sh`
4. **JSON output** — if field appears in recorder output: wrap with `json_escape` in `lib/recorder.sh`

## Tests that must pass after parser changes

```sh
bats tests/test_progress.sh
bats tests/test_parser.sh
bats tests/test_recorder.sh
```

The round-trip parity test (`922107b`) in `test_progress.sh` was written specifically to guard against sync regressions — run it first.
