#!/bin/sh

# Phase State Abstraction Layer
# Centralizes all eval-based phase variable access behind safe get/set helpers.
# Reduces ~130 scattered eval sites to ~4 in this file.
#
# Requires: phase_to_var() from lib/parser.sh (sourced before this file)

# Generic getter for PHASE_* variables
# Args: $1 - field name (e.g. STATUS, TITLE, ATTEMPTS)
#        $2 - phase number (e.g. 1, 2.5)
#        $3 - (optional) attempt number for compound keys (e.g. ATTEMPT_TIME)
# Returns: value on stdout
phase_get() {
  local _field="$1" _phase_num="$2"
  local _pv
  _pv=$(phase_to_var "$_phase_num")
  if [ $# -ge 3 ]; then
    eval "printf '%s' \"\${PHASE_${_field}_${_pv}_${3}:-}\""
  else
    eval "printf '%s' \"\${PHASE_${_field}_${_pv}:-}\""
  fi
}

# Generic setter for PHASE_* variables
# Args: $1 - field name (e.g. STATUS, TITLE, ATTEMPTS)
#        $2 - phase number (e.g. 1, 2.5)
#        $3 - value to set
#        $4 - (optional) attempt number for compound keys
# Escapes single quotes in values for safe eval.
phase_set() {
  local _field="$1" _phase_num="$2" _value="$3"
  local _pv _escaped
  _pv=$(phase_to_var "$_phase_num")
  _escaped=$(printf '%s' "$_value" | sed "s/'/'\\\\''/g")
  if [ $# -ge 4 ]; then
    eval "PHASE_${_field}_${_pv}_${4}='${_escaped}'"
  else
    eval "PHASE_${_field}_${_pv}='${_escaped}'"
  fi
}

# Convenience getters
get_phase_status()       { phase_get STATUS "$1"; }
get_phase_attempts()     { phase_get ATTEMPTS "$1"; }
get_phase_start_time()   { phase_get START_TIME "$1"; }
get_phase_end_time()     { phase_get END_TIME "$1"; }
get_phase_fail_reason()  { phase_get FAIL_REASON "$1"; }
get_phase_attempt_time() { phase_get ATTEMPT_TIME "$1" "$2"; }
get_phase_refactor_status() { phase_get REFACTOR_STATUS "$1"; }
get_phase_refactor_sha()    { phase_get REFACTOR_SHA "$1"; }
get_phase_refactor_attempts() { phase_get REFACTOR_ATTEMPTS "$1"; }
get_phase_consec_fail() {
  local _val
  _val=$(phase_get CONSEC_FAIL "$1")
  printf '%s' "${_val:-0}"
}

# Reset phase for retry: decrement attempts, clear last attempt time, set pending.
# Does NOT call write_progress — callers control timing.
# Args: $1 - phase number
reset_phase_for_retry() {
  local _phase_num="$1"
  local _attempts
  _attempts=$(get_phase_attempts "$_phase_num")
  case "$_attempts" in ''|*[!0-9]*) _attempts=0 ;; esac
  phase_set STATUS "$_phase_num" "pending"
  if [ "$_attempts" -gt 0 ]; then
    phase_set ATTEMPT_TIME "$_phase_num" "" "$_attempts"
    phase_set ATTEMPTS "$_phase_num" "$((_attempts - 1))"
  fi
  phase_set CONSEC_FAIL "$_phase_num" "0"
}

# Full reset to defaults (for --phase, --reset, plan-change additions)
# Args: $1 - phase number
reset_phase_full() {
  local _phase_num="$1"
  phase_set STATUS "$_phase_num" "pending"
  phase_set ATTEMPTS "$_phase_num" "0"
  phase_set START_TIME "$_phase_num" ""
  phase_set END_TIME "$_phase_num" ""
  phase_set FAIL_REASON "$_phase_num" ""
  phase_set REFACTOR_STATUS "$_phase_num" ""
  phase_set REFACTOR_SHA "$_phase_num" ""
  phase_set REFACTOR_ATTEMPTS "$_phase_num" ""
  phase_set CONSEC_FAIL "$_phase_num" "0"
}

# --- _OLD_PHASE_* namespace (for plan-change detection) ---

# Generic getter for _OLD_PHASE_* variables
# Args: $1 - field name (TITLE, STATUS, ATTEMPTS, START_TIME, END_TIME, DEPS)
#        $2 - phase number
#        $3 - (optional) attempt number
old_phase_get() {
  local _field="$1" _phase_num="$2"
  local _pv
  _pv=$(phase_to_var "$_phase_num")
  if [ $# -ge 3 ]; then
    eval "printf '%s' \"\${_OLD_PHASE_${_field}_${_pv}_${3}:-}\""
  else
    eval "printf '%s' \"\${_OLD_PHASE_${_field}_${_pv}:-}\""
  fi
}

# Generic setter for _OLD_PHASE_* variables
# Args: $1 - field name, $2 - phase number, $3 - value, $4 - (optional) attempt number
old_phase_set() {
  local _field="$1" _phase_num="$2" _value="$3"
  local _pv _escaped
  _pv=$(phase_to_var "$_phase_num")
  _escaped=$(printf '%s' "$_value" | sed "s/'/'\\\\''/g")
  if [ $# -ge 4 ]; then
    eval "_OLD_PHASE_${_field}_${_pv}_${4}='${_escaped}'"
  else
    eval "_OLD_PHASE_${_field}_${_pv}='${_escaped}'"
  fi
}

# auto_commit_changes(phase_num, label)
# Commits any uncommitted changes with a descriptive message.
# Non-fatal: logs warning on failure, always returns 0.
auto_commit_changes() {
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    if ! git add -A || ! git commit -q -m "Phase $1: $2"; then
      print_warning "Phase $1: auto-commit failed ($2)"
    fi
  fi
}
