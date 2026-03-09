# 26. Phase State Abstraction Layer

**Date:** 2026-03-09
**Status:** Accepted (supersedes ad-hoc eval in [0003](0003-eval-based-dynamic-variables.md))

## Context

The codebase had ~130 scattered `eval` calls for reading and writing phase variables (`PHASE_STATUS_N`, `PHASE_ATTEMPTS_N`, etc.) across 7 files. Each call site independently handled `phase_to_var` conversion and single-quote escaping, creating:

- **Duplication:** The same `phase_to_var` + `eval` pattern repeated everywhere
- **Inconsistency:** `PHASE_DESCRIPTION` used double-quote eval (unsafe) while others used single-quote with pre-escaping
- **Maintenance burden:** Adding a new phase field required updating every consumer
- **Error risk:** Forgetting to escape values at any site could cause injection

## Decision

Introduce `lib/phase_state.sh` with centralized get/set primitives:

- `phase_get(field, phase_num [, attempt_num])` — generic getter
- `phase_set(field, phase_num, value [, attempt_num])` — generic setter with single-quote escaping
- Convenience wrappers: `get_phase_status`, `get_phase_attempts`, etc.
- Reset helpers: `reset_phase_for_retry` (decrement + pending), `reset_phase_full` (defaults)
- `old_phase_get/old_phase_set` for the `_OLD_PHASE_*` namespace (plan-change detection)

All eval-based phase variable access is now confined to ~8 eval calls in `phase_state.sh`. The existing `get_phase_title`, `get_phase_description`, `get_phase_dependencies` in `parser.sh` became thin wrappers delegating to `phase_get`.

Sourced after `parser.sh` (needs `phase_to_var`), before all other libraries.

## Consequences

**Positive:**
- Single place to audit eval safety (8 sites vs 130+)
- Consistent escaping for all fields including DESCRIPTION
- `reset_phase_for_retry` eliminates 4 duplicated reset blocks
- New phase fields only need changes in `phase_state.sh`
- Existing tests required only sourcing changes (no logic changes)

**Negative:**
- Extra function call + subshell per access (~200ms overhead for 20 phases × 10 fields) — negligible vs Claude invocation time
- All test files must source `phase_state.sh` after `parser.sh`
