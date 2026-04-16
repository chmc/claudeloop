---
name: arch
description: Architecture reference — data model, libraries, execution flow, packaging sync, PROGRESS.md registry
---

# Architecture Reference

## Shell dialect

POSIX `#!/bin/sh`. No bashisms (arrays, `[[ ]]`, `local` in functions is acceptable per SC3043). All libraries must be sourceable by dash/ash.

## Data model

Phase data in flat numbered variables (dots replaced with underscores in var names):
```
PHASE_TITLE_N         PHASE_DESCRIPTION_N    PHASE_DEPENDENCIES_N  (space-separated nums)
PHASE_STATUS_N        (pending|in_progress|completed|failed)
PHASE_ATTEMPTS_N      PHASE_START_TIME_N     PHASE_END_TIME_N
PHASE_COUNT           (total number of phases)
PHASE_NUMBERS         (space-separated ordered list, e.g. "1 2 2.5 2.6 3")
VERIFY_PHASES         (true|false, default false)
REFACTOR_PHASES       (true|false, default false)
LIVE_LOG              (path to .claudeloop/live.log; empty string during dry-run)
.claudeloop/signals/phase-N.md  (no-changes signal file; written by Claude when phase needs no code changes)
```

Phase numbers may be decimals (e.g. `2.5`). The dot is replaced with underscore for variable names: `PHASE_TITLE_2_5`. Two helpers defined in `lib/parser.sh` and available everywhere:

```sh
phase_to_var "2.5"          # → "2_5"  (used before every eval)
phase_less_than "2.5" "3"   # → exit 0 (true); uses awk for correct float comparison
```

Read/write pattern used everywhere:
```sh
phase_var=$(phase_to_var "$phase_num")
value=$(eval "echo \"\$PHASE_STATUS_${phase_var}\"")
eval "PHASE_STATUS_${phase_var}='completed'"
```

Prefer `phase_get`/`phase_set` from `lib/phase_state.sh` for new code. Raw eval shown for reading existing code and parsers.

Iteration pattern (replaces old `i=1; while [ "$i" -le "$PHASE_COUNT" ]` loops):
```sh
for phase_num in $PHASE_NUMBERS; do
  phase_var=$(phase_to_var "$phase_num")
  ...
done
```

## Libraries

| File | Key functions |
|------|--------------|
| `lib/parser.sh` | `parse_plan` → sets all `PHASE_*_N` vars and `PHASE_COUNT` |
| `lib/ai_parser.sh` | `ai_parse_plan`, `ai_verify_plan`, `ai_reparse_with_feedback`, `ai_parse_and_verify`, `show_ai_plan`, `confirm_ai_plan`, `ai_parse_no_retry` (`--no-retry`: single pass, exit 2 on failure), `ai_parse_feedback` (`--ai-parse-feedback`: reparse from ai-verify-reason.txt, no live.log archival) |
| `lib/dependencies.sh` | `find_next_phase`, `is_phase_runnable`, `detect_dependency_cycles` (DFS, space-separated visited/stack strings) |
| `lib/phase_state.sh` | `phase_get`, `phase_set`, `get_phase_status`, `reset_phase_for_retry`, `reset_phase_full`, `auto_commit_changes` |
| `lib/progress.sh` | `init_progress`, `read_progress`, `write_progress`, `update_phase_status` |
| `lib/plan_changes.sh` | `transfer_attempt_fields`, `read_old_phase_list`, `detect_plan_changes`, `detect_orphan_logs`, `recover_progress_from_logs` |
| `lib/prompt.sh` | `build_phase_prompt`, `capture_git_context`, `build_default_prompt`, `apply_retry_strategy` |
| `lib/retry.sh` | `calculate_backoff`, `should_retry_phase`, `has_write_actions`, `has_signal_file`, `retry_strategy`, `escalate_strategy`, `verify_mode`, `extract_error_context`, `extract_verify_error`, `build_retry_context` |
| `lib/stream_processor.sh` | `process_stream_json` (AWK-based stream parser), `inject_heartbeats` |
| `lib/ui.sh` | `print_header`, `print_phase_status`, `print_all_phases`, `print_phase_exec_header`, `print_success/error/warning`, `log_verbose` |
| `lib/config.sh` | `load_config`, `write_config`, `update_conf_key`, `run_setup_wizard` |
| `lib/verify.sh` | `verify_phase`, `check_verdict` — read-only verification, verdict-based pass/fail (`VERIFICATION_PASSED`/`VERIFICATION_FAILED`), JSON-aware anti-skip check, stream processor integration, timeout |
| `lib/refactor.sh` | `build_refactor_prompt`, `verify_refactor`, `refactor_phase`, `run_refactor_if_needed` — opt-in auto-refactoring with git rollback |
| `lib/execution.sh` | `execute_phase`, `run_claude_pipeline`, `evaluate_phase_result`, `run_adaptive_verification`, `update_fail_reason` |
| `lib/archive.sh` | `archive_current_run`, `list_archives`, `restore_archive`, `generate_archive_metadata`, `is_run_complete`, `prompt_archive_completed_run` |
| `lib/recorder.sh` | `rec_load_progress`, `inject_and_write_html`, `generate_replay`, `assemble_recorder_json`, `safe_json_array`, `safe_json_object`, `validate_json` |
| `lib/recorder_overview.sh` | `rec_extract_run_overview`, `_rec_overview_from_metadata`, `_rec_aggregate_sessions` |
| `lib/recorder_parsers.sh` | `rec_extract_session`, `rec_extract_tools`, `rec_extract_files`, `rec_extract_tool_calls`, `rec_verify_verdict` |
| `lib/release_notes.sh` | `format_release_notes` |
| `claudeloop` | Orchestrator: arg parsing, `trap handle_interrupt INT TERM`, lock file, `main_loop` |

## Execution flow

```
main → parse_plan → init_progress → main_loop
  find_next_phase → execute_phase → verify_phase → refactor_phase → update_phase_status → write_progress
  no-changes:  signal file (.claudeloop/signals/phase-N.md) + successful session → skip verification → complete
  on failure:  should_retry_phase → retry_strategy → calculate_backoff → sleep → retry (standard/stripped/targeted)
  on Ctrl+C:   handle_interrupt → rollback refactor (if active) → write_progress (skip recorder) → fork recorder bg → save_state → exit 130
  --monitor:   run_monitor → tail -f .claudeloop/live.log
```

All `print_*` output (via `lib/ui.sh`) and stream processor output are teed to `.claudeloop/live.log` via `LIVE_LOG` (set in `main()` after `setup_project`; empty during dry-run).

## Packaging

Runtime files ship via three mechanisms that must stay in sync:

| Mechanism | File | What to update |
|-----------|------|----------------|
| Release tarball | `.github/workflows/release.yml` | `Build release tarball` step |
| Installer | `install.sh` | `cp`/`mkdir` commands |
| Installer tests | `tests/test_install.sh` | assert file exists after install |

Currently packaged: `claudeloop`, `lib/*.sh`, `assets/replay-template.html`.

## PROGRESS.md field registry

`write_progress` / `generate_phase_details` in `lib/progress.sh` is the source of truth for PROGRESS.md fields. Three parsers read this format:

| Parser | File | Namespace | Notes |
|--------|------|-----------|-------|
| `read_progress` | `lib/progress.sh` | `PHASE_*` | Validates status enum, normalizes in_progress |
| `read_old_phase_list` | `lib/plan_changes.sh` | `_OLD_PHASE_*` | Normalizes in_progress, no validation |
| `rec_load_progress` | `lib/recorder.sh` | `_REC_PHASE_*` | No normalization (preserves raw state) |

When adding fields to `write_progress`, update all three parsers. A round-trip parity test in `test_progress.sh` enforces this. Per-attempt fields must also be added to `transfer_attempt_fields()` in `lib/plan_changes.sh`.
