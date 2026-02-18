#!/bin/sh

# Phase Parser Library
# Parses PLAN.md files and extracts phase information

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
  PHASE_COUNT=0

  local current_phase=""
  local current_description=""
  local in_phase=false
  local line_num=0
  local expected_phase=1

  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))

    # Check if this is a phase header: ## Phase N: Title
    case "$line" in
      "## Phase "*)
        if echo "$line" | grep -qE '^##[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
          local phase_num
          phase_num=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
          local phase_title
          phase_title=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*[0-9][0-9]*:[[:space:]]*\(.*\)/\1/p')

          # Save previous phase description if exists
          if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
            _desc="$current_description"
            eval "PHASE_DESCRIPTION_${current_phase}=\"\${_desc}\""
          fi

          # Validate sequential numbering
          if [ "$phase_num" -ne "$expected_phase" ]; then
            echo "Error: Phase numbers must be sequential. Expected Phase $expected_phase, found Phase $phase_num at line $line_num" >&2
            return 1
          fi

          # Check for duplicate phase numbers (caught by sequential check above, but be explicit)
          local existing_title
          existing_title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
          if [ -n "$existing_title" ]; then
            echo "Error: Duplicate phase number $phase_num at line $line_num" >&2
            return 1
          fi

          # Store phase title (escape single quotes for eval safety)
          local phase_title_escaped
          phase_title_escaped=$(printf '%s' "$phase_title" | sed "s/'/'\\\\''/g")
          eval "PHASE_TITLE_${phase_num}='${phase_title_escaped}'"

          # Initialize dependencies to empty
          eval "PHASE_DEPENDENCIES_${phase_num}=''"

          current_phase="$phase_num"
          current_description=""
          in_phase=true
          PHASE_COUNT=$phase_num
          expected_phase=$((expected_phase + 1))
        fi
        ;;
      *)
        if [ "$in_phase" = true ]; then
          # Check for dependency declaration: **Depends on:** Phase X, Phase Y
          case "$line" in
            "**Depends on:**"*)
              local deps_line
              deps_line=$(echo "$line" | sed 's/^\*\*Depends[[:space:]]*on:[[:space:]]*\*\*[[:space:]]*//')
              local deps
              deps=$(echo "$deps_line" | sed 's/Phase //g' | grep -oE '[0-9]+' | xargs echo)
              eval "PHASE_DEPENDENCIES_${current_phase}='$deps'"
              ;;
            *)
              # Accumulate description
              if [ -n "$current_description" ]; then
                current_description="${current_description}
${line}"
              else
                current_description="$line"
              fi
              ;;
          esac
        fi
        ;;
    esac
  done < "$plan_file"

  # Save last phase description
  if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
    _desc="$current_description"
    eval "PHASE_DESCRIPTION_${current_phase}=\"\${_desc}\""
  fi

  # Validate dependencies
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$i\"")
    if [ -n "$deps" ]; then
      for dep in $deps; do
        local dep_title
        dep_title=$(eval "echo \"\$PHASE_TITLE_$dep\"")
        if [ -z "$dep_title" ]; then
          echo "Error: Phase $i depends on non-existent Phase $dep" >&2
          return 1
        fi
        if [ "$dep" -ge "$i" ]; then
          echo "Error: Phase $i cannot depend on Phase $dep (forward or self dependency)" >&2
          return 1
        fi
      done
    fi
    i=$((i + 1))
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
  eval "echo \"\$PHASE_TITLE_$phase_num\""
}

# Get description of a specific phase
# Args: $1 - phase number
get_phase_description() {
  local phase_num="$1"
  eval "echo \"\$PHASE_DESCRIPTION_$phase_num\""
}

# Get dependencies of a specific phase
# Args: $1 - phase number
# Returns: space-separated list of phase numbers
get_phase_dependencies() {
  local phase_num="$1"
  eval "echo \"\$PHASE_DEPENDENCIES_$phase_num\""
}

# Get all phase numbers
get_all_phases() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    echo "$i"
    i=$((i + 1))
  done
}
