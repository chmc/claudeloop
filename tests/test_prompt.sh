#!/usr/bin/env bash
# bats file_tags=prompt

# Test Phase Prompt Builder
# Written FIRST (TDD approach)

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/prompt.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Substitution mode (template contains {{...}}) ──────────────────────────

@test "substitution: {{PHASE_NUM}} is replaced" {
  printf 'Phase number: {{PHASE_NUM}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 3 "My Title" "My description" "PLAN.md")
  [ "$result" = "Phase number: 3" ]
}

@test "substitution: {{PHASE_TITLE}} is replaced" {
  printf 'Title: {{PHASE_TITLE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Setup DB" "desc" "PLAN.md")
  [ "$result" = "Title: Setup DB" ]
}

@test "substitution: {{PHASE_DESCRIPTION}} is replaced" {
  printf 'Desc: {{PHASE_DESCRIPTION}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Title" "Install packages" "PLAN.md")
  [ "$result" = "Desc: Install packages" ]
}

@test "substitution: {{PLAN_FILE}} is replaced" {
  printf 'File: {{PLAN_FILE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Title" "desc" "my-plan.md")
  [ "$result" = "File: my-plan.md" ]
}

@test "substitution: title with & is not corrupted" {
  printf 'Title: {{PHASE_TITLE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 "Foo & Bar" "desc" "PLAN.md")
  [ "$result" = "Title: Foo & Bar" ]
}

@test "substitution: title with backslash is not corrupted" {
  printf 'Title: {{PHASE_TITLE}}\n' > "$TEST_DIR/tpl.md"
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 1 'Foo\Bar' "desc" "PLAN.md")
  [ "$result" = 'Title: Foo\Bar' ]
}

@test "substitution: all four placeholders replaced simultaneously" {
  cat > "$TEST_DIR/tpl.md" << 'EOF'
/implement-using-swarm {{PHASE_TITLE}} @{{PLAN_FILE}}
Phase: {{PHASE_NUM}}
Description: {{PHASE_DESCRIPTION}}
EOF
  result=$(build_phase_prompt "$TEST_DIR/tpl.md" 2 "Add Auth" "Implement OAuth" "project.md")
  expected="/implement-using-swarm Add Auth @project.md
Phase: 2
Description: Implement OAuth"
  [ "$result" = "$expected" ]
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
