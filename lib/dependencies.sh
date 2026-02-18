#!/opt/homebrew/bin/bash

# Dependency Resolution Library
# Handles phase dependency checking, cycle detection, and execution order

# Check if a phase is runnable (all dependencies completed)
# Args: $1 - phase number
# Uses global: PHASE_DEPENDENCIES, PHASE_STATUS
# Returns: 0 if runnable, 1 if not
is_phase_runnable() {
  local phase_num="$1"
  local status="${PHASE_STATUS[$phase_num]}"

  # Phase must be pending or failed (not completed or in_progress)
  if [ "$status" != "pending" ] && [ "$status" != "failed" ]; then
    return 1
  fi

  # Check all dependencies are completed
  local deps="${PHASE_DEPENDENCIES[$phase_num]}"
  for dep in $deps; do
    if [ "${PHASE_STATUS[$dep]}" != "completed" ]; then
      return 1
    fi
  done

  return 0
}

# Find next runnable phase
# Uses global: PHASE_COUNT, PHASE_STATUS
# Returns: phase number (stdout) or empty if none
find_next_phase() {
  local i
  for i in $(seq 1 "$PHASE_COUNT"); do
    if is_phase_runnable "$i"; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

# Detect circular dependencies
# Returns: 0 if no cycles, 1 if cycle detected (with error message)
detect_dependency_cycles() {
  local phase
  local visited=()
  local rec_stack=()

  # DFS-based cycle detection
  for phase in $(seq 1 "$PHASE_COUNT"); do
    if ! _dfs_cycle_check "$phase"; then
      return 1
    fi
  done

  return 0
}

# Helper: DFS for cycle detection
# Args: $1 - current phase
_dfs_cycle_check() {
  local phase="$1"

  # Mark as visited in recursion stack
  if [[ " ${rec_stack[*]} " == *" $phase "* ]]; then
    echo "Error: Circular dependency detected involving Phase $phase" >&2
    return 1
  fi

  # Skip if already fully processed
  if [[ " ${visited[*]} " == *" $phase "* ]]; then
    return 0
  fi

  rec_stack+=("$phase")

  # Check all dependencies
  local deps="${PHASE_DEPENDENCIES[$phase]}"
  for dep in $deps; do
    if ! _dfs_cycle_check "$dep"; then
      return 1
    fi
  done

  # Remove from recursion stack, add to visited
  rec_stack=("${rec_stack[@]/$phase}")
  visited+=("$phase")

  return 0
}

# Get all phases that are blocked by a given phase
# Args: $1 - phase number
# Returns: space-separated list of blocked phase numbers
get_blocked_phases() {
  local blocker_phase="$1"
  local blocked=""
  local phase

  for phase in $(seq 1 "$PHASE_COUNT"); do
    local deps="${PHASE_DEPENDENCIES[$phase]}"
    if [[ " $deps " == *" $blocker_phase "* ]]; then
      blocked="$blocked $phase"
    fi
  done

  echo "${blocked# }"
}
