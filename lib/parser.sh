#!/bin/sh

# Phase Parser Library
# Parses PLAN.md files and extracts phase information

PHASE_COUNT=0
PHASE_NUMBERS=""

# Convert phase number to valid shell variable suffix: "2.5" -> "2_5"
phase_to_var() { echo "$1" | tr '.' '_'; }

# Returns 0 (true) if $1 < $2 as decimal numbers.
# Uses awk to handle float comparison correctly (e.g., 2.5 > 2.15).
phase_less_than() { awk -v a="$1" -v b="$2" 'BEGIN { exit (a < b ? 0 : 1) }'; }

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

    # Check if this is a phase header (flexible: 1-3 hashes or bare, case-insensitive, separator optional)
    if echo "$line" | grep -iqE '^#{1,3}[[:space:]]+[Pp]hase[[:space:]]+[0-9]+(\.[0-9]+)?([[:space:]]*:|[[:space:]]+-|[[:space:]]+[^-[:space:]]|[[:space:]]*$)|^[Pp]hase[[:space:]]+[0-9]+(\.[0-9]+)?([[:space:]]*:|[[:space:]]+-|[[:space:]]*$)'; then
      local phase_num
      phase_num=$(echo "$line" | sed -n 's/^[#]*[[:space:]]*[Pp][Hh][Aa][Ss][Ee][[:space:]]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p')
      local phase_title
      phase_title=$(echo "$line" | sed -n 's/^[#]*[[:space:]]*[Pp][Hh][Aa][Ss][Ee][[:space:]]*[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}[[:space:]]*[-:]*[[:space:]]*\(.*\)/\2/p' | sed 's/[[:space:]]*$//')
      if [ -z "$phase_title" ]; then
        phase_title="Phase $phase_num"
      fi

      # Save previous phase description if exists
      if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
        phase_set DESCRIPTION "$current_phase" "$current_description"
      fi

      # Validate ascending order
      if [ -n "$prev_phase" ] && ! phase_less_than "$prev_phase" "$phase_num"; then
        printf 'Error: Phase numbers must be in ascending order. "%s" follows "%s"\n' \
          "$phase_num" "$prev_phase" >&2
        return 1
      fi

      # Store phase title and initialize dependencies
      phase_set TITLE "$phase_num" "$phase_title"
      phase_set DEPENDENCIES "$phase_num" ""

      current_phase="$phase_num"
      current_description=""
      in_phase=true
      PHASE_COUNT=$((PHASE_COUNT + 1))
      prev_phase="$phase_num"
      PHASE_NUMBERS="${PHASE_NUMBERS:+$PHASE_NUMBERS }$phase_num"
    elif [ "$in_phase" = true ]; then
      # Check for dependency declaration: **Depends on:** Phase X, Phase Y
      case "$line" in
        "**Depends on:**"*)
          local deps_line
          deps_line=$(echo "$line" | sed 's/^\*\*Depends[[:space:]]*on:[[:space:]]*\*\*[[:space:]]*//')
          local deps
          deps=$(echo "$deps_line" | grep -oE 'Phase [0-9]+(\.[0-9]+)?' | sed 's/Phase //g' | xargs echo)
          phase_set DEPENDENCIES "$current_phase" "$deps"
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
  done < "$plan_file"

  # Save last phase description
  if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
    phase_set DESCRIPTION "$current_phase" "$current_description"
  fi

  # Validate dependencies
  for i in $PHASE_NUMBERS; do
    local deps
    deps=$(get_phase_dependencies "$i")
    if [ -n "$deps" ]; then
      for dep in $deps; do
        local dep_title
        dep_title=$(get_phase_title "$dep")
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
get_phase_title() { phase_get TITLE "$1"; }

# Get description of a specific phase
# Args: $1 - phase number
get_phase_description() { phase_get DESCRIPTION "$1"; }

# Get dependencies of a specific phase
# Args: $1 - phase number
# Returns: space-separated list of phase numbers
get_phase_dependencies() { phase_get DEPENDENCIES "$1"; }

# Get all phase numbers
get_all_phases() {
  for _phase in $PHASE_NUMBERS; do echo "$_phase"; done
}

# --- Progress file regex helpers ---
# These match the PROGRESS.md header format: ### <icon> Phase <num>: <title>

# Check if a line is a progress phase header
# Args: $1 - line to check
# Returns: 0 if match, 1 otherwise
is_progress_phase_header() {
  echo "$1" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+(\.[0-9]+)?:'
}

# Extract phase number from a progress phase header
# Args: $1 - line
# Prints phase number (e.g. "2.5") or empty string
extract_progress_phase_num() {
  echo "$1" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\):.*/\1/p'
}

# Extract title from a progress phase header
# Args: $1 - line
# Prints title or empty string
extract_progress_phase_title() {
  echo "$1" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}:[[:space:]]*\(.*\)/\2/p'
}

# Extract phase number from a log filename
# Args: $1 - file path (e.g. "/path/phase-2.5.log")
# Prints phase number or empty string
extract_log_phase_num() {
  printf '%s' "$1" | sed -n 's|.*/phase-\([0-9][0-9]*\(\.[0-9][0-9]*\)*\)\.log$|\1|p'
}
