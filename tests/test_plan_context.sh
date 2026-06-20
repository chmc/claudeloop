#!/usr/bin/env bash
# bats file_tags=prompt

# Test plan context injection into phase prompts
# Written FIRST (TDD approach)

setup() {
  export TEST_DIR="$BATS_TEST_TMPDIR"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  . "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  . "${BATS_TEST_DIRNAME}/../lib/prompt.sh"

  # Set up phase state for multi-phase tests
  PHASE_NUMBERS="1 2 3 4"
  phase_set TITLE 1 "Setup"
  phase_set STATUS 1 "completed"
  phase_set TITLE 2 "Core Features"
  phase_set STATUS 2 "completed"
  phase_set TITLE 3 "UI Components"
  phase_set STATUS 3 "in_progress"
  phase_set TITLE 4 "Animations"
  phase_set STATUS 4 "pending"

  # Create original plan file
  printf '# My Project Plan\n\nThis is the original plan.\n' \
    > "$TEST_DIR/original-plan.md"
}

teardown() {
  :
}

# ── build_plan_context ────────────────────────────────────────────────────

@test "build_plan_context: multi-phase plan produces phase index + file reference" {
  result=$(build_plan_context "3" "$TEST_DIR/original-plan.md")
  printf '%s' "$result" | grep -q "Phase 1: Setup"
  printf '%s' "$result" | grep -q "Phase 2: Core Features"
  printf '%s' "$result" | grep -q "\[CURRENT\]"
  printf '%s' "$result" | grep -q "Phase 4: Animations"
  printf '%s' "$result" | grep -q "original-plan.md"
}

@test "build_plan_context: returns empty when original plan file missing" {
  result=$(build_plan_context "1" "$TEST_DIR/nonexistent.md")
  [ -z "$result" ]
}

@test "build_plan_context: shows [FAILED] for failed phases" {
  phase_set STATUS 2 "failed"
  result=$(build_plan_context "3" "$TEST_DIR/original-plan.md")
  printf '%s' "$result" | grep -q "\[FAILED\]"
}

# ── build_default_prompt ───────────────────────────────────────────────────

@test "build_default_prompt: plan context appears inside ## Context section" {
  plan_ctx="- Phase 1: Setup [done]
- Phase 2: Core Features [CURRENT]
Read .claudeloop/original-plan.md for full plan."

  result=$(build_default_prompt "2" "Core Features" "Do the work" "" "$plan_ctx")

  # Context section contains plan context before existing bullets
  ctx_pos=$(printf '%s' "$result" | grep -n '## Context' | cut -d: -f1)
  plan_pos=$(printf '%s' "$result" | grep -n 'original-plan.md' | cut -d: -f1)
  [ -n "$ctx_pos" ] && [ -n "$plan_pos" ] && [ "$plan_pos" -gt "$ctx_pos" ]
}
