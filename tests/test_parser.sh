#!/opt/homebrew/bin/bash
# bats file_tags=parser

# Test Phase Parser
# These tests are written FIRST (TDD approach)

setup() {
  # Create temp directory for test files
  export TEST_DIR="$(mktemp -d)"
  # Source the parser
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
}

teardown() {
  # Clean up temp directory
  rm -rf "$TEST_DIR"
}

@test "parse_simple_plan: extracts correct number of phases" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# My Project Plan

## Phase 1: Setup
Create the initial setup.

## Phase 2: Implementation
Implement the feature.

## Phase 3: Testing
Add tests.
EOF

  # Don't use run here - we need global state to persist
  parse_plan "$TEST_DIR/PLAN.md"

  # Should have 3 phases
  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "parse_simple_plan: extracts phase titles correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup Database
Create database schema.

## Phase 2: Add API
Create REST endpoints.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup Database" ]

  run get_phase_title 2
  [ "$status" -eq 0 ]
  [ "$output" = "Add API" ]
}

@test "parse_simple_plan: extracts phase descriptions correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Create the initial setup.
This includes multiple lines.

## Phase 2: Implementation
Implement the feature.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_description 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Create the initial setup."* ]]
  [[ "$output" == *"This includes multiple lines."* ]]
}

@test "parse_dependencies: extracts dependency declarations" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Create database.

## Phase 2: API
**Depends on:** Phase 1

Create API endpoints.

## Phase 3: Tests
**Depends on:** Phase 2

Add tests.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_dependencies 2
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run get_phase_dependencies 3
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "parse_dependencies: handles multiple dependencies" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Create database.

## Phase 2: API
Create API.

## Phase 3: Integration
**Depends on:** Phase 1, Phase 2

Integrate everything.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_dependencies 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
  [[ "$output" == *"2"* ]]
}

@test "validate_plan: rejects non-sequential phase numbers" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Setup phase.

## Phase 3: Testing
Testing phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sequential"* ]] || [[ "$output" == *"Expected Phase 2"* ]]
}

@test "validate_plan: rejects duplicate phase numbers" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Setup phase.

## Phase 1: Another Setup
Another setup phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  # Duplicate is caught as sequential error: "Expected Phase 2, found Phase 1"
  [[ "$output" == *"duplicate"* ]] || [[ "$output" == *"Duplicate"* ]] || [[ "$output" == *"Expected Phase 2, found Phase 1"* ]]
}

@test "validate_plan: rejects invalid dependency references" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Setup phase.

## Phase 2: Implementation
**Depends on:** Phase 5

Implementation phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-existent"* ]] || [[ "$output" == *"invalid"* ]] || [[ "$output" == *"depends on"* ]]
}

@test "parse_plan: handles empty lines and spacing" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Project

## Phase 1: Setup

Create setup.


## Phase 2: Implementation

Implement feature.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "parse_plan: ignores non-phase headers" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Project Title

Some intro text.

## Phase 1: Setup
Create setup.

### Subsection
This is not a phase.

## Phase 2: Implementation
Implement feature.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}
