# 6. DFS Cycle Detection with Space-Separated Strings

**Date:** 2026-02-18
**Status:** Accepted

## Context

Phase dependencies form a directed graph. Circular dependencies (A → B → C → A) would cause infinite loops in the execution engine. Cycle detection is needed during plan validation to catch these before execution begins.

## Decision

Implement depth-first search (DFS) cycle detection using space-separated strings for the visited set and recursion stack. This replaces the original Bash implementation that used associative arrays.

The algorithm:
1. For each unvisited node, start a DFS traversal
2. Maintain a "visited" string and a "stack" string (nodes in the current path)
3. If a node is encountered that's already in the stack, a cycle exists
4. When backtracking, the node is removed from the stack but stays in visited

Set operations on space-separated strings:
```sh
# Check membership
case " $visited " in *" $node "*) echo "found" ;; esac

# Add to set
visited="$visited $node"
```

The `detect_dependency_cycles` function runs during `parse_plan` and reports the specific cycle path on failure.

## Consequences

**Positive:**
- Works within POSIX sh constraints (no associative arrays needed)
- Clear algorithmic approach — standard DFS with three-color marking
- Reports the cycle path for debugging, not just "cycle exists"
- Runs at parse time, preventing runtime failures

**Negative:**
- String-based set membership is O(n) per lookup instead of O(1) for hash-based sets
- Adequate for expected plan sizes (tens of phases) but would not scale to thousands
- Space-separated strings can't handle values containing spaces (phase numbers don't, so this is acceptable)
