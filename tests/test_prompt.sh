#!/usr/bin/env bash
# bats file_tags=prompt

# Test Phase Prompt Builder
# Written FIRST (TDD approach)

setup() {
  export TEST_DIR="$BATS_TEST_TMPDIR"
  export _NUDGE_DISABLED=1
  . "${BATS_TEST_DIRNAME}/../lib/nudge.sh"
  . "${BATS_TEST_DIRNAME}/../lib/prompt.sh"
}

teardown() {
  :
}

# ── Substitution mode (template contains {{...}}) ──────────────────────────

@test "substitution: {{PHASE_NUM}} is replaced" {
  printf 'Phase number: {{PHASE_NUM}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 3 "My Title" "My description" "PLAN.md")
  printf '%s' "$result" | grep -q "^Phase number: 3$"
}

@test "substitution: {{PHASE_TITLE}} is replaced" {
  printf 'Title: {{PHASE_TITLE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Setup DB" "desc" "PLAN.md")
  printf '%s' "$result" | grep -q "^Title: Setup DB$"
}

@test "substitution: {{PHASE_DESCRIPTION}} is replaced" {
  printf 'Desc: {{PHASE_DESCRIPTION}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Title" "Install packages" "PLAN.md")
  printf '%s' "$result" | grep -q "^Desc: Install packages$"
}

@test "substitution: {{PLAN_FILE}} is replaced" {
  printf 'File: {{PLAN_FILE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Title" "desc" "my-plan.md")
  printf '%s' "$result" | grep -q "^File: my-plan.md$"
}

@test "substitution: title with & is not corrupted" {
  printf 'Title: {{PHASE_TITLE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Foo & Bar" "desc" "PLAN.md")
  printf '%s' "$result" | grep -q "^Title: Foo & Bar$"
}

@test "substitution: title with backslash is not corrupted" {
  printf 'Title: {{PHASE_TITLE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 'Foo\Bar' "desc" "PLAN.md")
  printf '%s' "$result" | grep -q '^Title: Foo\\Bar$'
}

@test "substitution: all four placeholders replaced simultaneously" {
  cat > "$TEST_DIR/tpl.md" << 'EOF'
/implement-using-swarm {{PHASE_TITLE}} @{{PLAN_FILE}}
Phase: {{PHASE_NUM}}
Description: {{PHASE_DESCRIPTION}}
EOF
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 2 "Add Auth" "Implement OAuth" "project.md")
  printf '%s' "$result" | grep -q '^/implement-using-swarm Add Auth @project.md$'
  printf '%s' "$result" | grep -q '^Phase: 2$'
  printf '%s' "$result" | grep -q '^Description: Implement OAuth$'
}

# ── Append mode (no {{...}} in template) ───────────────────────────────────

@test "append mode: phase data block is appended when no placeholders" {
  printf 'Do the work carefully.\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 4 "Refactor" "Clean up the code" "PLAN.md")
  # Original content preserved
  printf '%s' "$result" | grep -q "Do the work carefully."
  # Phase data block appended
  printf '%s' "$result" | grep -q "## Phase Data"
}

@test "append mode: phase title appears in appended block" {
  printf 'Swarm instructions here.\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Deploy Service" "Deploy to prod" "PLAN.md")
  printf '%s' "$result" | grep -q "Deploy Service"
}

# ── Error handling ──────────────────────────────────────────────────────────

@test "empty template file returns error" {
  printf '' > "$TEST_DIR/empty.md"
  run build_phase_prompt "$TEST_DIR/empty.md" 1 "Title" "desc" "PLAN.md"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qi "empty"
}

# ── CLI flag acceptance ─────────────────────────────────────────────────────

@test "claudeloop accepts --phase-prompt flag with --dry-run" {
  printf 'Phase {{PHASE_NUM}}: {{PHASE_TITLE}}\n' > "$TEST_DIR/prompt.md"
  run "${BATS_TEST_DIRNAME}/../claudeloop" \
    --plan "${BATS_TEST_DIRNAME}/../examples/PLAN.md.example" \
    --dry-run \
    --phase-prompt "$TEST_DIR/prompt.md"
  [ "$status" -eq 0 ]
}

# ── append_subagent_model_instructions ──────────────────────────────────────

@test "append_subagent_model_instructions: injects instruction when SUBAGENT_MODEL_EXPLORE set" {
  SUBAGENT_MODEL_EXPLORE="haiku"
  result=$(append_subagent_model_instructions "base prompt text")
  printf '%s' "$result" | grep -q "Subagent Model Override"
  printf '%s' "$result" | grep -q '"Explore"'
  printf '%s' "$result" | grep -q '"haiku"'
}

@test "append_subagent_model_instructions: returns prompt unchanged when unset" {
  SUBAGENT_MODEL_EXPLORE=""
  result=$(append_subagent_model_instructions "base prompt text")
  [ "$result" = "base prompt text" ]
}

@test "append_subagent_model_instructions: uses configured model name verbatim" {
  SUBAGENT_MODEL_EXPLORE="sonnet"
  result=$(append_subagent_model_instructions "prompt")
  printf '%s' "$result" | grep -q '"sonnet"'
  ! printf '%s' "$result" | grep -q '"haiku"'
}

# ── build_default_prompt nudge injection ────────────────────────────────────

@test "build_default_prompt: nudge text injected after description when provided" {
  result=$(build_default_prompt "3" "Setup DB" "Create the schema" "" "" "use postgres not sqlite")
  printf '%s' "$result" | grep -q "use postgres not sqlite"
}

@test "build_default_prompt: nudge text appears after description before Context" {
  result=$(build_default_prompt "3" "Setup DB" "Create the schema" "" "" "my guidance")
  desc_pos=$(printf '%s' "$result" | grep -n "Create the schema" | head -1 | cut -d: -f1)
  nudge_pos=$(printf '%s' "$result" | grep -n "my guidance" | head -1 | cut -d: -f1)
  ctx_pos=$(printf '%s' "$result" | grep -n "## Context" | head -1 | cut -d: -f1)
  [ "$nudge_pos" -gt "$desc_pos" ]
  [ "$nudge_pos" -lt "$ctx_pos" ]
}

@test "build_default_prompt: nudge section has CRITICAL directive" {
  result=$(build_default_prompt "3" "Title" "Desc" "" "" "use approach X")
  printf '%s' "$result" | grep -q "CRITICAL"
}

@test "build_default_prompt: no nudge section when 6th arg absent" {
  result=$(build_default_prompt "3" "Title" "Desc" "" "")
  ! printf '%s' "$result" | grep -q "CRITICAL.*operator"
}

# ── apply_retry_strategy _FORCE_STANDARD_STRATEGY ───────────────────────────

@test "apply_retry_strategy: respects _FORCE_STANDARD_STRATEGY — stays standard" {
  # Stub dependencies
  get_phase_fail_reason() { printf 'stuck_loop'; }
  get_phase_consec_fail() { printf '5'; }
  retry_strategy() { printf 'standard'; }
  escalate_strategy() { printf 'stripped'; }  # would escalate without override
  build_retry_context() { printf ''; }
  MAX_RETRIES=3
  _FORCE_STANDARD_STRATEGY=true
  result=$(apply_retry_strategy "3" "4" "Title" "Desc" "" "" "original prompt")
  # Should not have replaced with stripped prompt ("You are a fresh instance")
  ! printf '%s' "$result" | grep -q "You are a fresh instance"
  unset _FORCE_STANDARD_STRATEGY
}

@test "apply_retry_strategy: escalates normally when _FORCE_STANDARD_STRATEGY unset" {
  get_phase_fail_reason() { printf 'stuck_loop'; }
  get_phase_consec_fail() { printf '5'; }
  retry_strategy() { printf 'stripped'; }
  escalate_strategy() { printf 'stripped'; }
  build_retry_context() { printf ''; }
  MAX_RETRIES=3
  unset _FORCE_STANDARD_STRATEGY
  result=$(apply_retry_strategy "3" "4" "Title" "Desc" "" "" "original prompt")
  printf '%s' "$result" | grep -q "You are a fresh instance"
}
