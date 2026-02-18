#!/bin/sh

# Dependency Resolution Library
# Handles phase dependency checking, cycle detection, and execution order

# Check if a phase is runnable (all dependencies completed)
# Args: $1 - phase number
# Uses global: PHASE_DEPENDENCIES_N, PHASE_STATUS_N
# Returns: 0 if runnable, 1 if not
is_phase_runnable() {
  local phase_num="$1"
  local status
  status=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")

  # Phase must be pending or failed (not completed or in_progress)
  if [ "$status" != "pending" ] && [ "$status" != "failed" ]; then
    return 1
  fi

  # Check all dependencies are completed
  local deps
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase_num\"")
  for dep in $deps; do
    local dep_status
    dep_status=$(eval "echo \"\$PHASE_STATUS_$dep\"")
    if [ "$dep_status" != "completed" ]; then
      return 1
    fi
  done

  return 0
}

# Find next runnable phase
# Uses global: PHASE_COUNT, PHASE_STATUS_N
# Returns: phase number (stdout) or empty if none
find_next_phase() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    if is_phase_runnable "$i"; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# Detect circular dependencies
# Returns: 0 if no cycles, 1 if cycle detected (with error message)
detect_dependency_cycles() {
  local visited=""
  local rec_stack=""

  # DFS-based cycle detection
  local phase=1
  while [ "$phase" -le "$PHASE_COUNT" ]; do
    if ! _dfs_cycle_check "$phase"; then
      return 1
    fi
    phase=$((phase + 1))
  done

  return 0
}

# Helper: DFS for cycle detection
# Args: $1 - current phase
# Uses/modifies outer scope: visited, rec_stack (space-separated strings)
_dfs_cycle_check() {
  local phase="$1"

  # Check if already on recursion stack (cycle detected)
  case " $rec_stack " in
    *" $phase "*)
      echo "Error: Circular dependency detected involving Phase $phase" >&2
      return 1
      ;;
  esac

  # Skip if already fully processed
  case " $visited " in
    *" $phase "*) return 0 ;;
  esac

  rec_stack="$rec_stack $phase"

  # Check all dependencies
  local deps
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase\"")
  for dep in $deps; do
    if ! _dfs_cycle_check "$dep"; then
      return 1
    fi
  done

  # Remove from recursion stack, add to visited
  local new_stack=""
  for item in $rec_stack; do
    [ "$item" != "$phase" ] && new_stack="$new_stack $item"
  done
  rec_stack="$new_stack"
  visited="$visited $phase"

  return 0
}

# Get all phases that are blocked by a given phase
# Args: $1 - phase number
# Returns: space-separated list of blocked phase numbers
get_blocked_phases() {
  local blocker_phase="$1"
  local blocked=""
  local phase=1

  while [ "$phase" -le "$PHASE_COUNT" ]; do
    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase\"")
    case " $deps " in
      *" $blocker_phase "*)
        blocked="$blocked $phase"
        ;;
    esac
    phase=$((phase + 1))
  done

  echo "${blocked# }"
}
