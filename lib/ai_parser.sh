#!/bin/sh

# AI Parser Library
# Uses claude CLI to decompose free-form plans into structured phases

# Run claude --print with streaming output and error handling
# Args: $1 - prompt text
# Returns: 0 on success (stdout = claude output), 1 on failure
# Streams output to stderr in real-time via process_stream_json
run_claude_print() {
  local prompt="$1"

  if ! command -v claude > /dev/null 2>&1; then
    print_error "claude CLI not found in PATH"
    return 1
  fi

  local tmp_prompt tmp_log tmp_raw _exit_tmp
  tmp_prompt=$(mktemp)
  tmp_log=$(mktemp)
  tmp_raw=$(mktemp)
  _exit_tmp=$(mktemp)
  printf '%s\n' "$prompt" > "$tmp_prompt"
  printf '1\n' > "$_exit_tmp"  # fail-safe default

  unset CLAUDECODE  # allow nested claude invocations (same pattern as execute_phase)

  # Stream-json pipeline: claude → inject_heartbeats → process_stream_json
  # process_stream_json stdout (timestamped text) → stderr (visible to user)
  # process_stream_json writes clean text to tmp_log
  {
    _rc=0
    claude --print --output-format=stream-json --verbose --include-partial-messages \
      < "$tmp_prompt" 2>&1 || _rc=$?
    printf '%s\n' "$_rc" > "$_exit_tmp"
  } | inject_heartbeats | process_stream_json "$tmp_log" "$tmp_raw" "false" "${LIVE_LOG:-}" "${SIMPLE_MODE:-false}" >&2

  local rc
  rc=$(cat "$_exit_tmp")

  if [ "$rc" -ne 0 ]; then
    print_error "claude --print failed with exit code $rc"
    rm -f "$tmp_prompt" "$tmp_log" "$tmp_raw" "$_exit_tmp"
    return 1
  fi

  # Strip process_stream_json metadata before returning
  grep -v '^\[.*\] model=' "$tmp_log" | grep -v '^\[Session:' > "${tmp_log}.clean"
  mv "${tmp_log}.clean" "$tmp_log"
  cat "$tmp_log"
  rm -f "$tmp_prompt" "$tmp_log" "$tmp_raw" "$_exit_tmp"
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

  # Build granularity-specific opening instruction
  local opening_instruction
  case "$granularity" in
    phases) opening_instruction="extract and organize them into 3-8 high-level phases, where each phase is a major milestone" ;;
    tasks)  opening_instruction="extract and organize them into 5-20 focused, independent tasks, where each task is completable in one AI session. IMPORTANT: Do NOT mirror the input's existing section structure — flatten sub-tasks into their own top-level phases" ;;
    steps)  opening_instruction="extract and organize them into 10-40 atomic steps, where each step is a single concrete action (create one file, write one function, run one test). IMPORTANT: Do NOT mirror the input's existing section structure — every sub-task becomes its own separate phase" ;;
    *)      opening_instruction="extract and organize them into 5-20 focused, independent tasks, where each task is completable in one AI session. IMPORTANT: Do NOT mirror the input's existing section structure — flatten sub-tasks into their own top-level phases" ;;
  esac

  # Build granularity-specific first CRITICAL RULE
  local grain_rule
  case "$granularity" in
    phases) grain_rule="Produce 3-8 high-level phases. Each phase is a major milestone." ;;
    tasks)  grain_rule="Produce 5-20 focused tasks. Each task should be completable in one AI session." ;;
    steps)  grain_rule="Produce 10-40 atomic steps. Each step is a single concrete action." ;;
    *)      grain_rule="Produce 5-20 focused tasks. Each task should be completable in one AI session." ;;
  esac

  # Decomposition example for tasks/steps (not phases)
  local decomp_example=""
  case "$granularity" in
    tasks|steps) decomp_example="
- DECOMPOSITION EXAMPLE: If the input has:
    \"Phase 1: Setup\" with sub-tasks \"1.1 Init project, 1.2 Design schema, 1.3 Write CRUD\"
  You must output:
    ## Phase 1: Init project
    (Part of: Setup)
    Description from original...

    ## Phase 2: Design schema
    (Part of: Setup)
    Description from original...

    ## Phase 3: Write CRUD
    (Part of: Setup)
    Description from original...
  Use the EXACT sub-task titles from the original — do NOT rephrase them.
  Add \"(Part of: [parent section name])\" as the first line of description for context.
  NOT a single \"## Phase 1: Project Setup & Database\" summarizing all three." ;;
  esac

  # Sub-task flattening rule for tasks/steps
  local flatten_rule=""
  case "$granularity" in
    tasks|steps) flatten_rule="
- If the input plan already has phases/sections with numbered sub-tasks (e.g. \"1.1\", \"1.2\"),
  each sub-task should become its OWN separate ## Phase, not grouped under one.
- When flattening sub-tasks into phases, add \"(Part of: [parent section name])\" as the FIRST line of each phase description. Include any relevant parent-level context that the sub-task needs to be self-contained." ;;
  esac

  # Execution context: strict for phases, relaxed for tasks/steps
  local exec_context
  case "$granularity" in
    phases) exec_context="- Therefore each phase description must be SELF-CONTAINED: include all necessary context, file paths, and specifications needed to complete the work independently" ;;
    *) exec_context="- Therefore each phase description must include enough context to execute independently.
  You may reference what prior phases created (e.g. \"the database schema from Phase 2\")
  rather than repeating full specifications in every phase." ;;
  esac

  local prompt
  prompt="You are a plan extraction assistant. Analyze the following plan/requirements and ${opening_instruction}.

YOUR TASK: Extract and preserve the original plan's content into structured phases. Do NOT rewrite, summarize, or paraphrase — copy the relevant original text as each phase's description.

CRITICAL RULES:
- ${grain_rule}${flatten_rule}${decomp_example}
- EXTRACT titles using the exact original wording from headings or sub-task titles — do not rephrase, shorten, expand, or invent new titles
- PRESERVE the relevant original content as each phase description — COPY the original bullet points and text. Do NOT summarize or rephrase. When flattening sub-tasks, add \"(Part of: [parent section])\" as the first description line so the executing AI has group context.
- Do NOT invent phases that do not exist in the original plan (e.g., do not add \"Final Code Review\" if the original lacks it)
- EXCLUDE non-phase sections — sections like \"Context\", \"Architecture Decision\", \"TDD Rules\", \"Scope Clarification\", \"Performance Criteria\", \"Project Structure\" are informational context, NOT executable phases. Do NOT create phases from them.
- Output markdown in this exact format:
  ## Phase 1: Title
  Description...

  ## Phase 2: Title
  **Depends on:** Phase 1
  Description...

- ALWAYS use \"## Phase N:\" headers. Never use \"Task\", \"Step\", or any other word — ONLY \"Phase\"
- Use INTEGER numbering only: 1, 2, 3, 4... (NO decimals)
- Add \"**Depends on:** Phase N, Phase M\" on the first line after header when a phase needs prior phases
- Do not add ANY text before the first \"## Phase\" or after the last phase description

EXECUTION CONTEXT — each phase will be:
- Executed by a SEPARATE, FRESH AI coding assistant instance
- The instance can only see this phase's description and the current git repository state
- It CANNOT see outputs, logs, or context from other phases
${exec_context}

PLAN TO EXTRACT FROM:
---
${plan_content}
---"

  print_success "Calling AI to decompose plan (granularity: $granularity)..."

  local ai_output
  ai_output=$(run_claude_print "$prompt") || {
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

    ai_output=$(run_claude_print "$retry_prompt") || return 1

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

  # Warn if AI appears to have rephrased titles
  validate_ai_titles "$cl_dir/ai-parsed-plan.md" "$plan_file"

  return 0
}

# Verify an AI-generated plan against the original
# Args: $1 - parsed plan file, $2 - original plan file, $3 - granularity (optional), $4 - claudeloop dir (optional)
# Returns: 0 on pass, 1 on fail
ai_verify_plan() {
  local parsed_file="$1"
  local original_file="$2"
  local granularity="${3:-tasks}"
  local cl_dir="${4:-.claudeloop}"

  local parsed_content original_content
  parsed_content=$(cat "$parsed_file")
  original_content=$(cat "$original_file")

  local granularity_context
  granularity_context="The decomposed plan uses \"${granularity}\" granularity.
- For \"phases\": expect 3-8 high-level phases
- For \"tasks\": expect 5-20 focused tasks (more phases than original sections is expected)
- For \"steps\": expect 10-40 atomic steps (many more phases than original sections is expected and correct)
Do NOT penalize the decomposed plan for having more phases than the original — that is the intended behavior."

  local prompt
  prompt="Compare the ORIGINAL requirements with the DECOMPOSED plan. Check:
1. COMPLETENESS: Every requirement from the original is covered in at least one phase
2. CORRECTNESS: Dependencies reference valid earlier phases, no circular deps
3. ORDERING: Phases are in logical execution order
4. CONTENT PRESERVATION: Phase titles must use the exact wording from original headings/sub-task titles (not rephrased). Phase descriptions must contain the original plan's text, not AI-rewritten summaries.

${granularity_context}

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
  verify_output=$(run_claude_print "$prompt") || return 1

  # Parse first line (case-insensitive, strip whitespace and punctuation)
  local first_line
  first_line=$(printf '%s\n' "$verify_output" | head -1 | tr -d '[:space:].:' | tr '[:lower:]' '[:upper:]')

  case "$first_line" in
    PASS)
      print_success "Verification passed"
      return 0
      ;;
    FAIL)
      local reason
      reason=$(printf '%s\n' "$verify_output" | tail -n +2)
      print_error "Verification failed: $reason"
      mkdir -p "$cl_dir"
      printf '%s\n' "$reason" > "$cl_dir/ai-verify-reason.txt"
      return 1
      ;;
    *)
      print_warning "Unexpected verification format (treating as fail): $first_line"
      return 1
      ;;
  esac
}

# Reparse plan with feedback from failed verification
# Args: $1 - original plan file, $2 - granularity, $3 - claudeloop dir (optional)
# Returns: 0 on success, 1 on failure
ai_reparse_with_feedback() {
  local plan_file="$1"
  local granularity="${2:-tasks}"
  local cl_dir="${3:-.claudeloop}"

  local plan_content previous_output failure_reason
  plan_content=$(cat "$plan_file")
  previous_output=$(cat "$cl_dir/ai-parsed-plan.md")
  failure_reason=$(cat "$cl_dir/ai-verify-reason.txt")

  # Build granularity-specific rule
  local grain_rule
  case "$granularity" in
    phases) grain_rule="Produce 3-8 high-level phases. Each phase is a major milestone." ;;
    tasks)  grain_rule="Produce 5-20 focused tasks. Each task should be completable in one AI session." ;;
    steps)  grain_rule="Produce 10-40 atomic steps. Each step is a single concrete action." ;;
    *)      grain_rule="Produce 5-20 focused tasks. Each task should be completable in one AI session." ;;
  esac

  local prompt
  prompt="You are a plan extraction assistant. Your previous extraction attempt FAILED verification.

VERIFICATION FAILURE REASON:
---
${failure_reason}
---

YOUR PREVIOUS (FAILED) OUTPUT:
---
${previous_output}
---

ORIGINAL PLAN TO EXTRACT FROM:
---
${plan_content}
---

Fix the issues identified above. Remember:
- ${grain_rule}
- EXTRACT and preserve the original plan's content — do NOT rewrite or summarize
- Titles must use the exact original wording from headings/sub-tasks — do NOT rephrase
- Do NOT invent phases that do not exist in the original plan
- EXCLUDE non-phase sections (Context, Architecture, TDD Rules, etc.)
- Output ONLY \"## Phase N: Title\" format, no preamble or commentary
- Use INTEGER numbering: 1, 2, 3... (NO decimals)
- Add \"**Depends on:** Phase N\" when a phase needs prior phases"

  print_success "Reparsing with feedback (granularity: $granularity)..."

  local ai_output
  ai_output=$(run_claude_print "$prompt") || return 1

  if [ -z "$ai_output" ]; then
    print_error "AI retry returned empty output"
    return 1
  fi

  # Extract ## Phase content
  local extracted
  extracted=$(printf '%s\n' "$ai_output" | awk '
    /^## Phase [0-9]/ { found=1 }
    found { print }
  ')

  if ! printf '%s\n' "$extracted" | grep -q '^## Phase [0-9]'; then
    print_error "AI retry output has no '## Phase N:' headers"
    return 1
  fi

  mkdir -p "$cl_dir"
  printf '%s\n' "$extracted" > "$cl_dir/ai-parsed-plan.md"

  local phase_count
  phase_count=$(printf '%s\n' "$extracted" | grep -c '^## Phase [0-9]')
  print_success "AI regenerated $phase_count phases"

  # Warn if AI appears to have rephrased titles
  validate_ai_titles "$cl_dir/ai-parsed-plan.md" "$plan_file"

  return 0
}

# Validate that AI-generated phase titles appear in the original plan text
# Args: $1 - parsed plan file, $2 - original plan file
# Prints a warning if less than half the titles match
validate_ai_titles() {
  local parsed_file="$1"
  local original_file="$2"

  local tmp_titles
  tmp_titles=$(mktemp)
  local original_content
  original_content=$(cat "$original_file")

  grep '^## Phase [0-9]' "$parsed_file" | sed 's/^## Phase [0-9]*:[[:space:]]*//' > "$tmp_titles"

  local match=0 total=0
  while IFS= read -r title; do
    total=$((total + 1))
    # Check if title (or significant words) appear in original
    if printf '%s\n' "$original_content" | grep -qF "$title"; then
      match=$((match + 1))
    fi
  done < "$tmp_titles"

  rm -f "$tmp_titles"

  if [ "$total" -gt 0 ] && [ "$match" -lt $((total / 2)) ]; then
    print_warning "Only $match/$total phase titles match original plan text — AI may have rephrased titles"
  fi
}

# Orchestrate AI parsing with verification feedback loop
# Args: $1 - plan file, $2 - granularity, $3 - claudeloop dir (optional)
# Returns: 0 on success, 1 on failure
ai_parse_and_verify() {
  local plan_file="$1"
  local granularity="${2:-tasks}"
  local cl_dir="${3:-.claudeloop}"
  local max_retries="${AI_RETRY_MAX:-3}"

  # Initial parse
  if ! ai_parse_plan "$plan_file" "$granularity" "$cl_dir"; then
    return 1
  fi

  local ai_plan="$cl_dir/ai-parsed-plan.md"
  local retry=0

  while true; do
    # Verify
    if ai_verify_plan "$ai_plan" "$plan_file" "$granularity" "$cl_dir"; then
      return 0
    fi

    retry=$((retry + 1))
    if [ "$retry" -gt "$max_retries" ]; then
      print_error "AI verification failed after $max_retries retries"
      return 1
    fi

    # Decide whether to retry
    if [ "${YES_MODE:-false}" = "true" ]; then
      print_warning "Auto-retrying (YES_MODE, attempt $retry/$max_retries)..."
    elif [ -n "${_AI_VERIFY_FORCE:-}" ] || [ -t 0 ]; then
      printf 'Send feedback to AI and retry? (Y/n) '
      read -r _answer
      case "$_answer" in
        [Nn]*) return 1 ;;
      esac
    else
      # Non-interactive, non-YES_MODE
      return 1
    fi

    # Reparse with feedback
    if ! ai_reparse_with_feedback "$plan_file" "$granularity" "$cl_dir"; then
      print_error "AI reparse failed"
      return 1
    fi
  done
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
