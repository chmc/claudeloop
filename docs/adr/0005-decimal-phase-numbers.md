# 5. Decimal Phase Numbers with Underscore Mapping

**Date:** 2026-02-20
**Status:** Accepted

## Context

Users needed to insert sub-phases between existing phases without renumbering the entire plan. For example, inserting work between Phase 2 and Phase 3 required either renumbering all subsequent phases or using a workaround.

## Decision

Support decimal phase numbers (e.g., `2.5`, `2.6`) in plan files. The mapping to shell variable names uses underscore substitution: phase `2.5` becomes `PHASE_TITLE_2_5`.

Key implementation details:

- `phase_to_var` converts dots to underscores for variable name construction
- `phase_less_than` uses AWK for correct floating-point comparison (shell arithmetic only handles integers)
- `PHASE_NUMBERS` holds the ordered list as a space-separated string: `"1 2 2.5 2.6 3"`
- Phase iteration uses `for phase_num in $PHASE_NUMBERS` instead of integer counting loops
- Dependencies reference decimal numbers directly: `**Depends on:** Phase 2.5`

```sh
phase_less_than() {
    awk "BEGIN { exit !($1 < $2) }"
}
```

## Consequences

**Positive:**
- Plans can be extended without renumbering — just insert `2.5` between `2` and `3`
- Natural notation that users already understand
- Backward compatible — integer-only plans work unchanged

**Negative:**
- Variable name mapping adds complexity (every access must go through `phase_to_var`)
- Float comparison requires AWK subprocess instead of shell arithmetic
- Iteration requires `PHASE_NUMBERS` list instead of simple `seq 1 $N` counting
- Dots in phase numbers could collide with other uses of dots in identifiers (mitigated by strict validation)
