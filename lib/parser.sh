#!/bin/sh

# Phase Parser Library
# Parses PLAN.md files and extracts phase information

PHASE_COUNT=0
PHASE_NUMBERS=""

# Convert phase number to valid shell variable suffix: "2.5" -> "2_5"
phase_to_var() { echo "$1" | tr '.' '_'; }

# Returns 0 (true) if $1 < $2 as decimal numbers.
# Uses awk to handle float comparison correctly (e.g., 2.5 > 2.15).
phase_less_than() { awk "BEGIN { exit ($1 < $2 ? 0 : 1) }"; }

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
  PHASE_NUMBERS=""

  local current_phase=""
  local current_description=""
  local in_phase=false
  local line_num=0
  local prev_phase=""

  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))

    # Check if this is a phase header: ## Phase N: Title (N may be decimal)
    case "$line" in
      "## Phase "*)
        if echo "$line" | grep -qE '^##[[:space:]]+Phase[[:space:]]+[0-9]+(\.[0-9]+)?:'; then
          local phase_num
          phase_num=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\):.*/\1/p')
          local phase_title
          phase_title=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}:[[:space:]]*\(.*\)/\2/p')

          # Save previous phase description if exists
          if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
            _desc="$current_description"
            local _prev_var
            _prev_var=$(phase_to_var "$current_phase")
            eval "PHASE_DESCRIPTION_${_prev_var}=\"\${_desc}\""
          fi

          # Validate ascending order
          if [ -n "$prev_phase" ] && ! phase_less_than "$prev_phase" "$phase_num"; then
            printf 'Error: Phase numbers must be in ascending order. "%s" follows "%s"\n' \
              "$phase_num" "$prev_phase" >&2
            return 1
          fi

          local phase_var
          phase_var=$(phase_to_var "$phase_num")

          # Check for duplicate phase numbers
          local existing_title
          existing_title=$(eval "echo \"\${PHASE_TITLE_${phase_var}:-}\"")
          if [ -n "$existing_title" ]; then
            echo "Error: Duplicate phase number $phase_num at line $line_num" >&2
            return 1
          fi

          # Store phase title (escape single quotes for eval safety)
          local phase_title_escaped
          phase_title_escaped=$(printf '%s' "$phase_title" | sed "s/'/'\\\\''/g")
          eval "PHASE_TITLE_${phase_var}='${phase_title_escaped}'"

          # Initialize dependencies to empty
          eval "PHASE_DEPENDENCIES_${phase_var}=''"

          current_phase="$phase_num"
          current_description=""
          in_phase=true
          PHASE_COUNT=$((PHASE_COUNT + 1))
          prev_phase="$phase_num"
          PHASE_NUMBERS="${PHASE_NUMBERS:+$PHASE_NUMBERS }$phase_num"
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
              deps=$(echo "$deps_line" | sed 's/Phase //g' | grep -oE '[0-9]+(\.[0-9]+)?' | xargs echo)
              local _cur_var
              _cur_var=$(phase_to_var "$current_phase")
              eval "PHASE_DEPENDENCIES_${_cur_var}='$deps'"
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
    local _last_var
    _last_var=$(phase_to_var "$current_phase")
    eval "PHASE_DESCRIPTION_${_last_var}=\"\${_desc}\""
  fi

  # Validate dependencies
  for i in $PHASE_NUMBERS; do
    local i_var
    i_var=$(phase_to_var "$i")
    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_${i_var}\"")
    if [ -n "$deps" ]; then
      for dep in $deps; do
        local dep_var
        dep_var=$(phase_to_var "$dep")
        local dep_title
        dep_title=$(eval "echo \"\${PHASE_TITLE_${dep_var}:-}\"")
        if [ -z "$dep_title" ]; then
          echo "Error: Phase $i depends on non-existent Phase $dep" >&2
          return 1
        fi
        if ! phase_less_than "$dep" "$i"; then
          echo "Error: Phase $i cannot depend on Phase $dep (forward or self dependency)" >&2
          return 1
        fi
      done
    fi
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
  local phase_var
  phase_var=$(phase_to_var "$phase_num")
  eval "echo \"\$PHASE_TITLE_${phase_var}\""
}

# Get description of a specific phase
# Args: $1 - phase number
get_phase_description() {
  local phase_num="$1"
  local phase_var
  phase_var=$(phase_to_var "$phase_num")
  eval "echo \"\$PHASE_DESCRIPTION_${phase_var}\""
}

# Get dependencies of a specific phase
# Args: $1 - phase number
# Returns: space-separated list of phase numbers
get_phase_dependencies() {
  local phase_num="$1"
  local phase_var
  phase_var=$(phase_to_var "$phase_num")
  eval "echo \"\$PHASE_DEPENDENCIES_${phase_var}\""
}

# Get all phase numbers
get_all_phases() {
  for _phase in $PHASE_NUMBERS; do echo "$_phase"; done
}
