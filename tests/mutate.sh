#!/usr/bin/env bash
# Mutation testing for claudeloop shell libraries.
#
# Applies small faults (one at a time) to lib/*.sh files, runs the
# corresponding bats test suite, and reports which mutations survived.
#
# Usage:
#   ./tests/mutate.sh                          # all lib files (excludes awk-heavy)
#   ./tests/mutate.sh lib/retry.sh             # single file
#   ./tests/mutate.sh --with-deletions         # include line-deletion mutations
#   ./tests/mutate.sh --with-integration       # re-test survivors against test_integration.sh
#
# Known limitations:
#   - `return 0` at end of functions may produce false survivors (equivalent to implicit return)
#   - Unquoted case patterns like `completed)` are not targeted
#   - Awk-heavy files (stream_processor.sh, prompt.sh) skipped by default
#   - Status literals in echo/printf lines may survive if tests don't assert on output text

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Options
WITH_DELETIONS=false
WITH_INTEGRATION=false
TIMEOUT=60

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# Totals
TOTAL=0
TOTAL_KILLED=0
TOTAL_SURVIVED=0
TOTAL_TIMEOUT=0

# Per-file stats stored in temp file (file|total|killed|survived|timeout)
STATS_FILE=""

# Survivors stored in temp file (file|line|op_info|orig_line)
SURVIVORS_FILE=""

# Target files stored in temp file
TARGETS_FILE=""

# Awk-heavy files excluded by default
AWK_HEAVY="stream_processor.sh prompt.sh"

# Deletion skip patterns (structural lines that shouldn't be deleted)
DELETION_SKIP_RE='^[[:space:]]*(#|$|\{|\}|fi|done|esac|else|elif|then|do|;;|local |shift|set [-+]|EOF|HEREDOC|#!/)'

usage() {
  printf "Usage: %s [--with-deletions] [--with-integration] [lib/file.sh ...]\n" "$(basename "$0")"
  exit 1
}

parse_args() {
  TARGETS_FILE=$(mktemp)
  while [ $# -gt 0 ]; do
    case "$1" in
      --with-deletions) WITH_DELETIONS=true ;;
      --with-integration) WITH_INTEGRATION=true ;;
      --help|-h) usage ;;
      lib/*.sh) echo "$1" >> "$TARGETS_FILE" ;;
      *) printf "Unknown argument: %s\n" "$1"; usage ;;
    esac
    shift
  done
}

preflight_check() {
  cd "$REPO_ROOT"
  if ! git diff --quiet lib/; then
    printf "${RED}Error: lib/ has uncommitted changes. Commit or stash first.${RESET}\n"
    exit 1
  fi
}

cleanup() {
  cd "$REPO_ROOT"
  git checkout -- lib/*.sh 2>/dev/null || true
  rm -f "$STATS_FILE" "$SURVIVORS_FILE" "$TARGETS_FILE" 2>/dev/null || true
}

resolve_targets() {
  if [ ! -s "$TARGETS_FILE" ]; then
    for f in lib/*.sh; do
      base="$(basename "$f")"
      skip=false
      for awk_file in $AWK_HEAVY; do
        if [ "$base" = "$awk_file" ]; then
          skip=true
          break
        fi
      done
      if [ "$skip" = false ]; then
        echo "$f" >> "$TARGETS_FILE"
      fi
    done
  fi
}

test_file_for() {
  local lib_file=$1
  local base
  base="$(basename "$lib_file" .sh)"
  echo "tests/test_${base}.sh"
}

# Mutation operators: name|match|replace|line_filter
OPERATORS='rel_eq_ne|-eq|-ne|\[ .* -eq
rel_ne_eq|-ne|-eq|\[ .* -ne
rel_lt_ge|-lt|-ge|\[ .* -lt
rel_ge_lt|-ge|-lt|\[ .* -ge
rel_gt_le|-gt|-le|\[ .* -gt
rel_le_gt|-le|-gt|\[ .* -le
str_eq_ne|= "|!= "|\[ .* = "
str_ne_eq|!= "|= "|\[ .* != "
bool_eq|= true|= false|= true
bool_ne|= false|= true|= false
exit_0_1|exit 0|exit 1|exit 0
exit_1_0|exit 1|exit 0|exit 1
ret_0_1|return 0|return 1|return 0
ret_1_0|return 1|return 0|return 1
status_comp_fail|"completed"|"failed"|"completed"
status_pend_comp|"pending"|"completed"|"pending"'

enumerate_mutations() {
  local file=$1
  local mut_file=$2

  > "$mut_file"

  local line_num=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))

    # Skip comment lines and blank lines
    local stripped="${line#"${line%%[![:space:]]*}"}"
    if [ -z "$stripped" ] || [ "${stripped#\#}" != "$stripped" ]; then
      continue
    fi

    # Apply each operator
    echo "$OPERATORS" | while IFS='|' read -r op_name op_match op_replace op_filter; do
      [ -z "$op_name" ] && continue

      # Skip eval lines for string operators
      if [ "$op_name" = "str_eq_ne" ] || [ "$op_name" = "str_ne_eq" ]; then
        if echo "$line" | grep -q 'eval'; then
          continue
        fi
      fi

      # Check line filter
      if ! echo "$line" | grep -qE "$op_filter"; then
        continue
      fi

      # Count occurrences on this line
      local count
      count=$(echo "$line" | grep -o -- "$op_match" | wc -l | tr -d ' ')
      if [ "$count" -eq 0 ]; then
        continue
      fi

      local occ=1
      while [ "$occ" -le "$count" ]; do
        local suffix=""
        if [ "$count" -gt 1 ]; then
          suffix=" (${occ})"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
          "$line_num" "$op_name" "$op_match" "$op_replace" "$occ" "$suffix" "$line" >> "$mut_file"
        occ=$((occ + 1))
      done
    done

    # Line deletion (opt-in)
    if [ "$WITH_DELETIONS" = true ]; then
      if ! echo "$line" | grep -qE "$DELETION_SKIP_RE"; then
        printf '%s|deletion|||||%s\n' "$line_num" "$line" >> "$mut_file"
      fi
    fi
  done < "$file"
}

apply_mutation() {
  local file=$1 line_num=$2 match=$3 replace=$4 occurrence=${5:-1}

  awk -v ln="$line_num" -v m="$match" -v r="$replace" -v occ="$occurrence" '
    NR==ln {
      n=0; s=$0; result=""
      while (match(s, m)) {
        n++
        if (n==occ) {
          result = result substr(s, 1, RSTART-1) r
          s = substr(s, RSTART+RLENGTH)
          result = result s
          s = ""
          break
        }
        result = result substr(s, 1, RSTART+RLENGTH-1)
        s = substr(s, RSTART+RLENGTH)
      }
      if (s != "") result = result s
      print result
      next
    }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

apply_deletion() {
  local file=$1 line_num=$2

  awk -v ln="$line_num" '
    NR==ln { print "# MUTANT_DELETED"; next }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

kill_tree() {
  local pid=$1
  # Recursively find and kill all descendants (children, grandchildren, etc.)
  local children
  children=$(pgrep -P "$pid" 2>/dev/null) || true
  for child in $children; do
    kill_tree "$child"
  done
  kill "$pid" 2>/dev/null || true
}

run_test_with_timeout() {
  local test_file=$1
  bats "$test_file" > /dev/null 2>&1 &
  local pid=$!
  ( sleep "$TIMEOUT" 2>/dev/null; kill_tree "$pid" ) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  TEST_EXIT_CODE=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  # Ensure no orphans survive (handles deeply nested children)
  kill_tree "$pid"
  return $TEST_EXIT_CODE
}

print_progress() {
  local idx=$1 total=$2 file=$3 line=$4 op=$5 suffix=$6 status=$7

  local color="$GREEN"
  local label="KILLED"
  if [ "$status" = "survived" ]; then
    color="$YELLOW"
    label="SURVIVED"
  elif [ "$status" = "timeout" ]; then
    color="$GREEN"
    label="TIMEOUT"
  fi

  printf "  [%3d/%-3d] %-28s %-20s ${color}%s${RESET}\n" \
    "$idx" "$total" "${file}:${line}" "${op}${suffix}" "$label"
}

# Get/set per-file stat from STATS_FILE
# Format: file|total|killed|survived|timeout
get_file_stat() {
  local file=$1 field=$2
  local line
  line=$(grep "^${file}|" "$STATS_FILE" 2>/dev/null || echo "")
  if [ -z "$line" ]; then
    echo 0
    return
  fi
  case "$field" in
    total)    echo "$line" | cut -d'|' -f2 ;;
    killed)   echo "$line" | cut -d'|' -f3 ;;
    survived) echo "$line" | cut -d'|' -f4 ;;
    timeout)  echo "$line" | cut -d'|' -f5 ;;
  esac
}

set_file_stats() {
  local file=$1 total=$2 killed=$3 survived=$4 timeout=$5
  local tmp
  tmp=$(mktemp)
  grep -v "^${file}|" "$STATS_FILE" > "$tmp" 2>/dev/null || true
  echo "${file}|${total}|${killed}|${survived}|${timeout}" >> "$tmp"
  mv "$tmp" "$STATS_FILE"
}

inc_file_stat() {
  local file=$1 field=$2
  local total killed survived timeout
  total=$(get_file_stat "$file" total)
  killed=$(get_file_stat "$file" killed)
  survived=$(get_file_stat "$file" survived)
  timeout=$(get_file_stat "$file" timeout)
  case "$field" in
    killed)   killed=$((killed + 1)) ;;
    survived) survived=$((survived + 1)) ;;
    timeout)  timeout=$((timeout + 1)) ;;
  esac
  set_file_stats "$file" "$total" "$killed" "$survived" "$timeout"
}

dec_file_stat() {
  local file=$1 field=$2
  local total killed survived timeout
  total=$(get_file_stat "$file" total)
  killed=$(get_file_stat "$file" killed)
  survived=$(get_file_stat "$file" survived)
  timeout=$(get_file_stat "$file" timeout)
  case "$field" in
    killed)   killed=$((killed - 1)) ;;
    survived) survived=$((survived - 1)) ;;
    timeout)  timeout=$((timeout - 1)) ;;
  esac
  set_file_stats "$file" "$total" "$killed" "$survived" "$timeout"
}

retest_survivors_with_integration() {
  local survivor_count
  survivor_count=$(wc -l < "$SURVIVORS_FILE" | tr -d ' ')
  if [ "$survivor_count" -eq 0 ]; then
    return
  fi
  if [ ! -f "$REPO_ROOT/tests/test_integration.sh" ]; then
    printf "${YELLOW}Warning: tests/test_integration.sh not found, skipping integration retest${RESET}\n"
    return
  fi

  printf "\n${BOLD}Re-testing %d survivors against test_integration.sh...${RESET}\n" "$survivor_count"

  local new_survivors
  new_survivors=$(mktemp)
  local retest_killed=0

  while IFS='|' read -r lib_file line_num op_info orig_line; do
    local op_name="${op_info%% (*}"
    op_name="${op_name%% *}"

    # Re-apply the mutation
    if [ "$op_name" = "deletion" ]; then
      apply_deletion "$REPO_ROOT/$lib_file" "$line_num"
    else
      echo "$OPERATORS" | while IFS='|' read -r name match replace _filter; do
        if [ "$name" = "$op_name" ]; then
          local occ=1
          case "$op_info" in
            *"("*")"*)
              occ=$(echo "$op_info" | sed 's/.*(\([0-9]*\)).*/\1/')
              ;;
          esac
          apply_mutation "$REPO_ROOT/$lib_file" "$line_num" "$match" "$replace" "$occ"
        fi
      done
    fi

    if run_test_with_timeout "$REPO_ROOT/tests/test_integration.sh"; then
      echo "${lib_file}|${line_num}|${op_info}|${orig_line}" >> "$new_survivors"
    else
      retest_killed=$((retest_killed + 1))
      TOTAL_KILLED=$((TOTAL_KILLED + 1))
      TOTAL_SURVIVED=$((TOTAL_SURVIVED - 1))
      inc_file_stat "$lib_file" killed
      dec_file_stat "$lib_file" survived
      printf "  %-28s %-20s ${GREEN}KILLED (integration)${RESET}\n" \
        "${lib_file}:${line_num}" "$op_info"
    fi

    cd "$REPO_ROOT"
    git checkout -- "$lib_file" 2>/dev/null
  done < "$SURVIVORS_FILE"

  mv "$new_survivors" "$SURVIVORS_FILE"
  printf "  Integration retest: %d additional kills\n" "$retest_killed"
}

print_summary() {
  printf "\n${BOLD}Summary:${RESET}\n"

  while IFS= read -r lib_file; do
    local total killed_n timeout_n survived score
    total=$(get_file_stat "$lib_file" total)
    if [ "$total" -eq 0 ]; then
      continue
    fi
    killed_n=$(get_file_stat "$lib_file" killed)
    timeout_n=$(get_file_stat "$lib_file" timeout)
    survived=$(get_file_stat "$lib_file" survived)
    local killed=$((killed_n + timeout_n))
    score=0
    if [ "$total" -gt 0 ]; then
      score=$(( (killed * 100) / total ))
    fi

    local color="$GREEN"
    if [ "$score" -lt 80 ]; then
      color="$RED"
    elif [ "$score" -lt 100 ]; then
      color="$YELLOW"
    fi

    printf "  %-28s %3d mutants  %3d killed  %3d survived  ${color}%3d%%${RESET}\n" \
      "$lib_file" "$total" "$killed" "$survived" "$score"
  done < "$TARGETS_FILE"

  local total_killed_all=$((TOTAL_KILLED + TOTAL_TIMEOUT))
  local total_score=0
  if [ "$TOTAL" -gt 0 ]; then
    total_score=$(( (total_killed_all * 100) / TOTAL ))
  fi

  local total_color="$GREEN"
  if [ "$total_score" -lt 80 ]; then
    total_color="$RED"
  elif [ "$total_score" -lt 100 ]; then
    total_color="$YELLOW"
  fi

  printf "  ────────────────────────────────────────────────────────────\n"
  printf "  ${BOLD}%-28s %3d mutants  %3d killed  %3d survived  ${total_color}%3d%%${RESET}\n" \
    "TOTAL" "$TOTAL" "$total_killed_all" "$TOTAL_SURVIVED" "$total_score"
}

write_report() {
  if [ "$TOTAL_SURVIVED" -eq 0 ]; then
    return
  fi

  mkdir -p "$REPO_ROOT/.claudeloop"
  local report="$REPO_ROOT/.claudeloop/mutation-report.md"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  {
    printf '# Mutation Testing Report\n'
    printf 'Generated: %s\n\n' "$timestamp"
    printf '## Summary\n'
    printf '| File | Mutants | Killed | Survived | Score |\n'
    printf '|------|---------|--------|----------|-------|\n'

    while IFS= read -r lib_file; do
      local total
      total=$(get_file_stat "$lib_file" total)
      if [ "$total" -eq 0 ]; then continue; fi
      local killed_n timeout_n survived
      killed_n=$(get_file_stat "$lib_file" killed)
      timeout_n=$(get_file_stat "$lib_file" timeout)
      survived=$(get_file_stat "$lib_file" survived)
      local killed=$((killed_n + timeout_n))
      local score=$(( (killed * 100) / total ))
      printf '| %s | %d | %d | %d | %d%% |\n' "$lib_file" "$total" "$killed" "$survived" "$score"
    done < "$TARGETS_FILE"

    local total_killed_all=$((TOTAL_KILLED + TOTAL_TIMEOUT))
    local total_score=0
    if [ "$TOTAL" -gt 0 ]; then
      total_score=$(( (total_killed_all * 100) / TOTAL ))
    fi
    printf '| **Total** | **%d** | **%d** | **%d** | **%d%%** |\n\n' \
      "$TOTAL" "$total_killed_all" "$TOTAL_SURVIVED" "$total_score"

    printf '## Surviving Mutants\n\n'

    local current_file=""
    while IFS='|' read -r lib_file line_num op_info orig_line; do
      if [ "$lib_file" != "$current_file" ]; then
        printf '### %s\n' "$lib_file"
        current_file="$lib_file"
      fi
      printf '#### Line %s — %s\n' "$line_num" "$op_info"
      printf '```\n'
      printf '  Original: %s\n' "$orig_line"

      # Show mutant line
      if [ "$op_info" = "deletion" ]; then
        printf '  Mutant:   # MUTANT_DELETED\n'
      else
        local op_name="${op_info%% (*}"
        op_name="${op_name%% *}"
        echo "$OPERATORS" | while IFS='|' read -r name match replace _filter; do
          if [ "$name" = "$op_name" ]; then
            local mutant_line
            mutant_line=$(echo "$orig_line" | sed "s|${match}|${replace}|")
            printf '  Mutant:   %s\n' "$mutant_line"
          fi
        done
      fi
      printf '```\n\n'
    done < "$SURVIVORS_FILE"
  } > "$report"

  printf "\nReport written to .claudeloop/mutation-report.md\n"
}

main() {
  parse_args "$@"
  preflight_check
  resolve_targets

  STATS_FILE=$(mktemp)
  SURVIVORS_FILE=$(mktemp)
  > "$STATS_FILE"
  > "$SURVIVORS_FILE"

  trap cleanup EXIT INT TERM

  printf "${BOLD}Mutation Testing Results${RESET}\n"
  printf "========================\n"

  # First pass: count total mutations for progress display
  local total_count=0
  while IFS= read -r lib_file; do
    local tmp
    tmp=$(mktemp)
    enumerate_mutations "$REPO_ROOT/$lib_file" "$tmp"
    local count
    count=$(wc -l < "$tmp" | tr -d ' ')
    total_count=$((total_count + count))
    rm -f "$tmp"
  done < "$TARGETS_FILE"

  TOTAL=$total_count
  local global_idx=0

  while IFS= read -r lib_file; do
    local test_file
    test_file="$(test_file_for "$lib_file")"

    if [ ! -f "$REPO_ROOT/$test_file" ]; then
      printf "${YELLOW}Warning: No test file %s for %s, skipping${RESET}\n" "$test_file" "$lib_file"
      continue
    fi

    local mut_file
    mut_file=$(mktemp)
    enumerate_mutations "$REPO_ROOT/$lib_file" "$mut_file"

    local file_mutations
    file_mutations=$(wc -l < "$mut_file" | tr -d ' ')
    if [ "$file_mutations" -eq 0 ]; then
      rm -f "$mut_file"
      continue
    fi

    set_file_stats "$lib_file" "$file_mutations" 0 0 0

    while IFS='|' read -r line_num op_name op_match op_replace occurrence suffix orig_line; do
      global_idx=$((global_idx + 1))

      # Apply mutation
      if [ "$op_name" = "deletion" ]; then
        apply_deletion "$REPO_ROOT/$lib_file" "$line_num"
      else
        apply_mutation "$REPO_ROOT/$lib_file" "$line_num" "$op_match" "$op_replace" "$occurrence"
      fi

      # Run tests
      local status="killed"
      TEST_EXIT_CODE=0
      run_test_with_timeout "$REPO_ROOT/$test_file" || true
      if [ "$TEST_EXIT_CODE" -eq 0 ]; then
        status="survived"
        inc_file_stat "$lib_file" survived
        TOTAL_SURVIVED=$((TOTAL_SURVIVED + 1))
        echo "${lib_file}|${line_num}|${op_name}${suffix}|${orig_line}" >> "$SURVIVORS_FILE"
      elif [ "$TEST_EXIT_CODE" -eq 137 ] || [ "$TEST_EXIT_CODE" -eq 143 ]; then
        status="timeout"
        inc_file_stat "$lib_file" timeout
        TOTAL_TIMEOUT=$((TOTAL_TIMEOUT + 1))
      else
        inc_file_stat "$lib_file" killed
        TOTAL_KILLED=$((TOTAL_KILLED + 1))
      fi

      print_progress "$global_idx" "$TOTAL" "$lib_file" "$line_num" "$op_name" "$suffix" "$status"

      # Restore
      cd "$REPO_ROOT"
      git checkout -- "$lib_file" 2>/dev/null
    done < "$mut_file"

    rm -f "$mut_file"
  done < "$TARGETS_FILE"

  if [ "$WITH_INTEGRATION" = true ]; then
    retest_survivors_with_integration
  fi

  print_summary
  write_report

  if [ "$TOTAL_SURVIVED" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

main "$@"
