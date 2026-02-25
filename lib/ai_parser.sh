#!/bin/sh

# AI Parser Library
# Uses claude CLI to decompose free-form plans into structured phases

# Run claude --print with timeout and error handling
# Args: $1 - prompt text, $2 - timeout in seconds
# Returns: 0 on success (stdout = claude output), 1 on failure, 2 on timeout
# Streams output to stderr in real-time via two-stage pipe (tee >&2)
run_claude_print() {
  local prompt="$1"
  local timeout_secs="${2:-120}"

  if ! command -v claude > /dev/null 2>&1; then
    print_error "claude CLI not found in PATH"
    return 1
  fi

  local tmp_prompt tmp_out tmp_err _exit_tmp
  tmp_prompt=$(mktemp)
  tmp_out=$(mktemp)
  tmp_err=$(mktemp)
  _exit_tmp=$(mktemp)
  printf '%s\n' "$prompt" > "$tmp_prompt"
  printf '1\n' > "$_exit_tmp"  # fail-safe default

  unset CLAUDECODE  # allow nested claude invocations (same pattern as execute_phase)

  # Two-stage pipe: claude stdout → tee (saves to file + copies to stderr)
  # stderr→terminal is line-buffered = real-time streaming
  # Exit code written to _exit_tmp (POSIX-safe, no PIPESTATUS)
  {
    _rc=0
    if command -v timeout > /dev/null 2>&1; then
      timeout "$timeout_secs" claude --print < "$tmp_prompt" 2> "$tmp_err" || _rc=$?
    else
      # POSIX fallback: background + sleep + kill
      claude --print < "$tmp_prompt" 2> "$tmp_err" &
      _cpid=$!
      # Close stdout in timer subshell so sleep doesn't hold pipe open
      ( sleep "$timeout_secs"; kill "$_cpid" 2>/dev/null ) >/dev/null 2>&1 &
      _tpid=$!
      wait "$_cpid" 2>/dev/null || _rc=$?
      kill "$_tpid" 2>/dev/null || true
      wait "$_tpid" 2>/dev/null || true
    fi
    printf '%s\n' "$_rc" > "$_exit_tmp"
  } | tee "$tmp_out" >&2

  local rc
  rc=$(cat "$_exit_tmp")

  case "$rc" in
    124|143|137)
      print_error "claude --print timed out after ${timeout_secs}s"
      rm -f "$tmp_prompt" "$tmp_out" "$tmp_err" "$_exit_tmp"
      return 2 ;;
  esac

  if [ "$rc" -ne 0 ]; then
    local err_msg
    err_msg=$(cat "$tmp_err")
    if [ -n "$err_msg" ]; then
      print_error "claude --print failed: $err_msg"
    else
      print_error "claude --print failed with exit code $rc"
    fi
    rm -f "$tmp_prompt" "$tmp_out" "$tmp_err" "$_exit_tmp"
    return 1
  fi

  # Batch-log to live.log for --monitor visibility
  if [ -n "${LIVE_LOG:-}" ] && [ -s "$tmp_out" ]; then
    log_live "[ai-parse] --- AI response ---"
    while IFS= read -r _line; do
      log_live "  $_line"
    done < "$tmp_out"
  fi

  cat "$tmp_out"
  rm -f "$tmp_prompt" "$tmp_out" "$tmp_err" "$_exit_tmp"
  return 0
}

# Parse a plan file using AI
# Args: $1 - plan file path, $2 - granularity (phases|tasks|steps), $3 - claudeloop dir (optional)
# Returns: 0 on success, 1 on failure
ai_parse_plan() {
  local plan_file="$1"
  local granularity="${2:-tasks}"
  local cl_dir="${3:-.claudeloop}"

  local plan_content
  plan_content=$(cat "$plan_file")

  # Build granularity instruction
  local grain_instruction
  case "$granularity" in
    phases) grain_instruction="Break into 3-8 high-level phases. Each phase is a major milestone." ;;
    tasks)  grain_instruction="Break into focused tasks. Each should be completable in one AI session. Aim for 5-20 total items." ;;
    steps)  grain_instruction="Break into atomic steps. Each step is a single action (create one file, write one function, run one test). Aim for 10-40 total items." ;;
    *)      grain_instruction="Break into focused tasks. Each should be completable in one AI session. Aim for 5-20 total items." ;;
  esac

  local prompt
  prompt="You are a plan decomposition assistant. Analyze the following plan/requirements and break them into sequential phases.

CRITICAL RULES:
- Output ONLY markdown in this exact format, nothing else:
  ## Phase 1: Title
  Description...

  ## Phase 2: Title
  **Depends on:** Phase 1
  Description...

- ALWAYS use \"## Phase N:\" headers. Never use \"Task\", \"Step\", or any other word — ONLY \"Phase\"
- Use INTEGER numbering only: 1, 2, 3, 4... (NO decimals)
- Add \"**Depends on:** Phase N, Phase M\" on the first line after header when a phase needs prior phases
- Do not add ANY text before the first \"## Phase\" or after the last phase description
- ${grain_instruction}

EXECUTION CONTEXT — each phase will be:
- Executed by a SEPARATE, FRESH AI coding assistant instance
- The instance can only see this phase's description and the current git repository state
- It CANNOT see outputs, logs, or context from other phases
- Therefore each phase description must be SELF-CONTAINED: include all necessary context, file paths, and specifications needed to complete the work independently

PLAN TO DECOMPOSE:
---
${plan_content}
---"

  print_success "Calling AI to decompose plan (granularity: $granularity)..."

  local ai_output
  ai_output=$(run_claude_print "$prompt" 120) || {
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      return 1
    fi
    return 1
  }

  # Validate output is not empty
  if [ -z "$ai_output" ]; then
    print_error "AI returned empty output"
    return 1
  fi

  # Extract ## Phase content (strip preamble/postamble)
  local extracted
  extracted=$(printf '%s\n' "$ai_output" | awk '
    /^## Phase [0-9]/ { found=1 }
    found { print }
  ')

  # Validate: at least one ## Phase header
  local validation_error=""
  if ! printf '%s\n' "$extracted" | grep -q '^## Phase [0-9]'; then
    validation_error="No '## Phase N:' headers found in output"
  fi

  # Retry once on validation failure
  if [ -n "$validation_error" ]; then
    print_warning "AI output validation failed: $validation_error"
    print_warning "Retrying with corrective prompt..."

    local retry_prompt="${prompt}

Your previous output was invalid: ${validation_error}
Please output ONLY the ## Phase markdown format as specified. No preamble, no commentary."

    ai_output=$(run_claude_print "$retry_prompt" 120) || return 1

    if [ -z "$ai_output" ]; then
      print_error "AI retry returned empty output"
      return 1
    fi

    extracted=$(printf '%s\n' "$ai_output" | awk '
      /^## Phase [0-9]/ { found=1 }
      found { print }
    ')

    if ! printf '%s\n' "$extracted" | grep -q '^## Phase [0-9]'; then
      print_error "AI retry also failed validation: No '## Phase N:' headers found"
      return 1
    fi
  fi

  # Write to output file
  mkdir -p "$cl_dir"
  printf '%s\n' "$extracted" > "$cl_dir/ai-parsed-plan.md"

  local phase_count
  phase_count=$(printf '%s\n' "$extracted" | grep -c '^## Phase [0-9]')
  print_success "AI generated $phase_count phases"

  return 0
}

# Verify an AI-generated plan against the original
# Args: $1 - parsed plan file, $2 - original plan file
# Returns: 0 on pass, 1 on fail
ai_verify_plan() {
  local parsed_file="$1"
  local original_file="$2"

  local parsed_content original_content
  parsed_content=$(cat "$parsed_file")
  original_content=$(cat "$original_file")

  local prompt
  prompt="Compare the ORIGINAL requirements with the DECOMPOSED plan. Check:
1. COMPLETENESS: Every requirement from the original is covered in at least one phase
2. CORRECTNESS: Dependencies reference valid earlier phases, no circular deps
3. ORDERING: Phases are in logical execution order

Respond with EXACTLY:
- Line 1: \"PASS\" if correct, or \"FAIL\" if not
- If FAIL: lines 2+ explain what's wrong

ORIGINAL:
---
${original_content}
---

DECOMPOSED:
---
${parsed_content}
---"

  print_success "Verifying AI-generated plan against original..."

  local verify_output
  verify_output=$(run_claude_print "$prompt" 120) || return 1

  # Parse first line
  local first_line
  first_line=$(printf '%s\n' "$verify_output" | head -1 | tr -d '[:space:]')

  case "$first_line" in
    PASS)
      print_success "Verification passed"
      return 0
      ;;
    FAIL)
      local reason
      reason=$(printf '%s\n' "$verify_output" | tail -n +2)
      print_error "Verification failed: $reason"
      return 1
      ;;
    *)
      print_warning "Unexpected verification format (treating as pass): $first_line"
      return 0
      ;;
  esac
}

# Display the AI-generated plan
# Args: $1 - parsed plan file
show_ai_plan() {
  local parsed_file="$1"

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  log_live "═══════════════════════════════════════════════════════════"
  echo "AI-generated plan:"
  log_live "AI-generated plan:"
  echo "═══════════════════════════════════════════════════════════"
  log_live "═══════════════════════════════════════════════════════════"
  echo ""
  cat "$parsed_file"
  # Log plan content to live.log for --monitor visibility
  if [ -n "${LIVE_LOG:-}" ]; then
    while IFS= read -r _line; do
      log_live "  $_line"
    done < "$parsed_file"
  fi
  echo ""

  local phase_count
  phase_count=$(grep -c '^## Phase [0-9]' "$parsed_file")
  echo "───────────────────────────────────────────────────────────"
  log_live "───────────────────────────────────────────────────────────"
  echo "$phase_count phases total"
  log_live "$phase_count phases total"
  echo "───────────────────────────────────────────────────────────"
  log_live "───────────────────────────────────────────────────────────"
}

# Confirm AI-generated plan with the user
# Args: $1 - parsed plan file
# Returns: 0 on accept, 1 on reject
confirm_ai_plan() {
  local parsed_file="$1"

  show_ai_plan "$parsed_file"

  # Auto-approve in non-interactive contexts
  if [ "${YES_MODE:-false}" = "true" ] || [ "${DRY_RUN:-false}" = "true" ]; then
    print_success "Auto-approved (non-interactive mode)"
    return 0
  fi

  # Auto-approve when stdin is not a TTY (CI, piped input, Claude-as-executor)
  if [ -z "${_AI_CONFIRM_FORCE:-}" ] && [ ! -t 0 ]; then
    print_success "Auto-approved (non-interactive input)"
    return 0
  fi

  # Interactive confirmation loop
  while true; do
    printf 'Accept? (Y/n/e) '
    read -r _answer
    case "$_answer" in
      ''|[Yy]*)
        return 0
        ;;
      [Nn]*)
        print_warning "Plan rejected by user"
        return 1
        ;;
      [Ee]*)
        ${EDITOR:-vi} "$parsed_file"
        # Validate edited content
        if ! grep -q '^## Phase [0-9]' "$parsed_file"; then
          print_error "Edited plan is invalid: no ## Phase headers found"
          show_ai_plan "$parsed_file"
          continue
        fi
        # Check it parses correctly
        if parse_plan "$parsed_file" 2>/dev/null; then
          return 0
        else
          print_error "Edited plan failed validation"
          show_ai_plan "$parsed_file"
          continue
        fi
        ;;
      *)
        continue
        ;;
    esac
  done
}
