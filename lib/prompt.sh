#!/bin/sh

# Prompt Building Library
# Handles prompt construction for phase execution: template-based prompts,
# default prompts, git context injection, and retry strategy prompt modification.

build_phase_prompt() {
  local template_file="$1"
  local phase_num="$2"
  local title="$3"
  local description="$4"
  local plan_file="$5"
  local prompt

  if [ ! -s "$template_file" ]; then
    printf 'Error: phase prompt template produced empty output: %s\n' "$template_file" >&2
    return 1
  fi

  if grep -qF '{{' "$template_file"; then
    # Substitution mode.
    # Use split()-based replacement (NOT gsub) to safely handle & and \ in values.
    prompt=$(PHASE_NUM="$phase_num" \
             PHASE_TITLE="$title" \
             PHASE_DESCRIPTION="$description" \
             PLAN_FILE="$plan_file" \
             awk '
      function replace_all(str, needle, repl,    parts, n, i, result) {
        n = split(str, parts, needle)
        result = parts[1]
        for (i = 2; i <= n; i++) result = result repl parts[i]
        return result
      }
      {
        line = $0
        line = replace_all(line, "{{PHASE_NUM}}",         ENVIRON["PHASE_NUM"])
        line = replace_all(line, "{{PHASE_TITLE}}",       ENVIRON["PHASE_TITLE"])
        line = replace_all(line, "{{PHASE_DESCRIPTION}}", ENVIRON["PHASE_DESCRIPTION"])
        line = replace_all(line, "{{PLAN_FILE}}",         ENVIRON["PLAN_FILE"])
        print line
      }' "$template_file")
  else
    # Append mode: attach phase data block after template content.
    prompt=$(cat "$template_file"; printf '\n---\n## Phase Data\n- Phase Number: %s\n- Phase Title: %s\n- Plan File: %s\n\n### Description\n%s\n' \
      "$phase_num" "$title" "$plan_file" "$description")
  fi

  if [ -z "$prompt" ]; then
    printf 'Error: phase prompt template produced empty output: %s\n' "$template_file" >&2
    return 1
  fi

  printf '%s' "$prompt"
}

# Capture current git state for prompt context injection
# Returns: git context string on stdout (empty if no git info)
capture_git_context() {
  local _git_stat _git_log_lines
  _git_stat=$(git diff --stat 2>/dev/null)
  _git_log_lines=$(git log --oneline -3 2>/dev/null)
  if [ -n "$_git_stat" ] || [ -n "$_git_log_lines" ]; then
    printf '\n## Current Git State\n'
    [ -n "$_git_log_lines" ] && printf 'Recent commits:\n%s\n' "$_git_log_lines"
    [ -n "$_git_stat" ] && printf 'Uncommitted changes:\n%s\n' "$_git_stat"
  fi
}

# Build default prompt for a phase (when no custom prompt template is used)
# Args: $1 - phase_num, $2 - title, $3 - description, $4 - git_context
# Returns: prompt string on stdout
build_default_prompt() {
  local _bdp_phase="$1" _bdp_title="$2" _bdp_desc="$3" _bdp_git="$4"
  printf '%s' "You are executing Phase $_bdp_phase of a multi-phase plan.

## Phase $_bdp_phase: $_bdp_title

$_bdp_desc

## Context
- This is a fresh Claude instance dedicated to this phase only
- Previous phases have been completed and committed to git
- Even if prior work for this phase exists in git, you MUST complete every subtask listed in the description above — do not assume the phase is done
- Review recent git history and existing code before implementing
- When done, ensure all changes are tested and working
- Commit your changes when complete
- If the phase requires no code changes (already implemented, verification-only), write a brief summary of your findings to .claudeloop/signals/phase-${_bdp_phase}.md explaining why no changes were needed
${_bdp_git}
## Task
Implement the above phase completely. Make sure to:
1. Read relevant existing code
2. Implement required changes
3. Test your implementation thoroughly
4. Commit your changes when complete"
}

# Apply retry strategy: archive log, build retry context, optionally replace prompt
# Args: $1 - phase_num, $2 - attempt, $3 - title, $4 - description,
#        $5 - git_context, $6 - log_file, $7 - current prompt
# Returns: modified prompt on stdout
apply_retry_strategy() {
  local _ars_phase="$1" _ars_attempt="$2" _ars_title="$3" _ars_desc="$4"
  local _ars_git="$5" _ars_log="$6" _ars_prompt="$7"
  local _fail_reason _strategy _prev_verify_log _retry_ctx

  local _consec
  _fail_reason=$(get_phase_fail_reason "$_ars_phase")
  _consec=$(get_phase_consec_fail "$_ars_phase")
  _strategy=$(retry_strategy "$_ars_attempt" "$MAX_RETRIES")
  _strategy=$(escalate_strategy "$_strategy" "$_fail_reason" "$_consec")

  # Archive previous attempt log (used for retry prompt context)
  if [ -f "$_ars_log" ]; then
    cp "$_ars_log" "${_ars_log%.log}.attempt-$((_ars_attempt - 1)).log"
  fi

  _prev_verify_log=".claudeloop/logs/phase-$_ars_phase.verify.log"
  [ -f "$_prev_verify_log" ] || _prev_verify_log=""

  # For stripped/targeted strategies, replace the base prompt with a simpler one
  if [ "$_strategy" = "stripped" ] && [ -z "$PHASE_PROMPT_FILE" ]; then
    _ars_prompt="You are a fresh instance. Previous phases are done.

## Phase $_ars_phase: $_ars_title

$_ars_desc
${_ars_git}"
  elif [ "$_strategy" = "targeted" ] && [ -z "$PHASE_PROMPT_FILE" ]; then
    _ars_prompt="## Phase $_ars_phase: $_ars_title
${_ars_git}"
  fi

  # Build and inject retry context
  _retry_ctx=$(build_retry_context "$_strategy" "$_ars_attempt" "$MAX_RETRIES" "$_fail_reason" "$_ars_log" "$_prev_verify_log" "$_consec")
  if [ -n "$_retry_ctx" ]; then
    _ars_prompt="${_ars_prompt}

${_retry_ctx}"
  fi

  printf '%s' "$_ars_prompt"
}
