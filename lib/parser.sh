#!/opt/homebrew/bin/bash

# Phase Parser Library
# Parses PLAN.md files and extracts phase information
# Requires bash 4.0+ for associative arrays

# Global associative arrays to store parsed phase data
declare -A PHASE_TITLES
declare -A PHASE_DESCRIPTIONS
declare -A PHASE_DEPENDENCIES
PHASE_COUNT=0

# Parse a PLAN.md file
# Args: $1 - path to PLAN.md file
# Returns: 0 on success, non-zero on error
parse_plan() {
  local plan_file="$1"

  if [ ! -f "$plan_file" ]; then
    echo "Error: Plan file not found: $plan_file" >&2
    return 1
  fi

  # Reset global state
  PHASE_TITLES=()
  PHASE_DESCRIPTIONS=()
  PHASE_DEPENDENCIES=()
  PHASE_COUNT=0

  local current_phase=""
  local current_description=""
  local in_phase=false
  local line_num=0
  local expected_phase=1

  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))

    # Check if this is a phase header: ## Phase N: Title
    if [[ "$line" =~ ^##\ +Phase\ +([0-9]+):\ *(.*) ]]; then
      local phase_num="${BASH_REMATCH[1]}"
      local phase_title="${BASH_REMATCH[2]}"

      # Save previous phase if exists
      if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
        PHASE_DESCRIPTIONS[$current_phase]="$current_description"
      fi

      # Validate sequential numbering
      if [ "$phase_num" -ne "$expected_phase" ]; then
        echo "Error: Phase numbers must be sequential. Expected Phase $expected_phase, found Phase $phase_num at line $line_num" >&2
        return 1
      fi

      # Check for duplicate phase numbers
      if [ -n "${PHASE_TITLES[$phase_num]:-}" ]; then
        echo "Error: Duplicate phase number $phase_num at line $line_num" >&2
        return 1
      fi

      # Start new phase
      PHASE_TITLES[$phase_num]="$phase_title"
      current_phase="$phase_num"
      current_description=""
      in_phase=true
      PHASE_COUNT=$phase_num
      expected_phase=$((expected_phase + 1))

    elif [ "$in_phase" = true ]; then
      # Check for dependency declaration: **Depends on:** Phase X, Phase Y
      if [[ "$line" =~ ^\*\*Depends\ +on:\*\*\ +(.*) ]]; then
        local deps_str="${BASH_REMATCH[1]}"
        local deps=""

        # Extract phase numbers from dependency string using grep
        # This avoids nested bracket issues with regex
        local temp_str="$deps_str"
        while [[ "$temp_str" =~ Phase\ +([0-9]+) ]]; do
          local dep_num="${BASH_REMATCH[1]}"
          deps="$deps $dep_num"
          # Remove the matched part
          temp_str="${temp_str#*${BASH_REMATCH[0]}}"
        done

        # Store dependencies (trim leading space)
        PHASE_DEPENDENCIES[$current_phase]="${deps# }"
      else
        # Accumulate description
        if [ -n "$current_description" ]; then
          current_description+=$'\n'
        fi
        current_description+="$line"
      fi
    fi
  done < "$plan_file"

  # Save last phase description
  if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
    PHASE_DESCRIPTIONS[$current_phase]="$current_description"
  fi

  # Validate dependencies
  for phase_num in "${!PHASE_DEPENDENCIES[@]}"; do
    local deps="${PHASE_DEPENDENCIES[$phase_num]}"
    for dep in $deps; do
      if [ -z "${PHASE_TITLES[$dep]:-}" ]; then
        echo "Error: Phase $phase_num depends on non-existent Phase $dep" >&2
        return 1
      fi
      if [ "$dep" -ge "$phase_num" ]; then
        echo "Error: Phase $phase_num cannot depend on Phase $dep (forward or self dependency)" >&2
        return 1
      fi
    done
  done

  if [ "$PHASE_COUNT" -eq 0 ]; then
    echo "Error: No phases found in plan file" >&2
    return 1
  fi

  return 0
}

# Get total number of phases
get_phase_count() {
  echo "$PHASE_COUNT"
}

# Get title of a specific phase
# Args: $1 - phase number
get_phase_title() {
  local phase_num="$1"
  echo "${PHASE_TITLES[$phase_num]}"
}

# Get description of a specific phase
# Args: $1 - phase number
get_phase_description() {
  local phase_num="$1"
  echo "${PHASE_DESCRIPTIONS[$phase_num]}"
}

# Get dependencies of a specific phase
# Args: $1 - phase number
# Returns: space-separated list of phase numbers
get_phase_dependencies() {
  local phase_num="$1"
  echo "${PHASE_DEPENDENCIES[$phase_num]}"
}

# Get all phase numbers
get_all_phases() {
  for i in $(seq 1 "$PHASE_COUNT"); do
    echo "$i"
  done
}
