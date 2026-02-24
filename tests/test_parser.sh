#!/usr/bin/env bash
# bats file_tags=parser

# Test Phase Parser
# These tests are written FIRST (TDD approach)

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
}

teardown() {
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

  parse_plan "$TEST_DIR/PLAN.md"

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

@test "validate_plan: rejects out-of-order phase numbers (gaps now allowed)" {
  # Gaps are allowed; only descending order is rejected
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Setup phase.

## Phase 3: Testing
Testing phase.
EOF

  # This should now SUCCEED since 1 < 3 is ascending
  parse_plan "$TEST_DIR/PLAN.md"
  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
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
  # Duplicate is caught either as "not ascending" or "duplicate"
  [[ "$output" == *"duplicate"* ]] || [[ "$output" == *"Duplicate"* ]] || [[ "$output" == *"ascending"* ]] || [[ "$output" == *"order"* ]]
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

@test "parse_plan: handles single-quote in phase title" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Install 'foo' package
Install the foo package.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"* ]]
}

@test "parse_plan: preserves dollar sign in description without expanding" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Configure
Set the $DEBUG variable to true.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_description 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'$DEBUG'* ]]
}

@test "validate_plan: rejects forward dependency" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
**Depends on:** Phase 2

Setup phase.

## Phase 2: Implementation
Implementation phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"forward"* ]] || [[ "$output" == *"cannot depend"* ]]
}

# --- Decimal phase number tests ---

@test "parse_plan: parses decimal phases 1 2 2.5 2.6 3 correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2: Core
Do core.

## Phase 2.5: Hotfix
Do hotfix.

## Phase 2.6: Followup
Do followup.

## Phase 3: Finalize
Wrap up.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "parse_plan: PHASE_NUMBERS contains decimal phases in order" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2: Core
Do core.

## Phase 2.5: Hotfix
Do hotfix.

## Phase 2.6: Followup
Do followup.

## Phase 3: Finalize
Wrap up.
EOF

  parse_plan "$TEST_DIR/PLAN.md"
  [ "$PHASE_NUMBERS" = "1 2 2.5 2.6 3" ]
}

@test "parse_plan: decimal phase title stored with underscore variable" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2.5: Hotfix
Do hotfix.

## Phase 3: Finalize
Wrap up.
EOF

  parse_plan "$TEST_DIR/PLAN.md"
  [ "$PHASE_TITLE_2_5" = "Hotfix" ]
}

@test "validate_plan: rejects out-of-order phases (3 2 1)" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 3: Finalize
Wrap up.

## Phase 2: Core
Do core.

## Phase 1: Setup
Do setup.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ascending"* ]] || [[ "$output" == *"order"* ]]
}

@test "validate_plan: rejects out-of-order decimal (1 2 1.5 3)" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2: Core
Do core.

## Phase 1.5: Late insertion
Should be rejected.

## Phase 3: Finalize
Wrap up.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ascending"* ]] || [[ "$output" == *"order"* ]]
}

@test "validate_plan: rejects duplicate decimal (1 2 2 3)" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2: Core
Do core.

## Phase 2: Another Core
Should be rejected.

## Phase 3: Finalize
Wrap up.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
}

@test "parse_plan: decimal dependency parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2: Core
Do core.

## Phase 2.5: Hotfix
**Depends on:** Phase 2

Do hotfix.

## Phase 3: Finalize
**Depends on:** Phase 2.5

Wrap up.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_dependencies 2.5
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_dependencies 3
  [ "$status" -eq 0 ]
  [ "$output" = "2.5" ]
}

# --- Flexible semantic phase header tests ---

@test "flexible_headers: single hash '# Phase 1: Setup' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Phase 1: Setup
Create setup.

# Phase 2: Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]
}

@test "flexible_headers: triple hash '### Phase 1: Setup' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
### Phase 1: Setup
Create setup.

### Phase 2: Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]
}

@test "flexible_headers: lowercase '## phase 1: Setup' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## phase 1: Setup
Create setup.

## phase 2: Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]
}

@test "flexible_headers: uppercase '## PHASE 1: SETUP' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## PHASE 1: SETUP
Create setup.

## PHASE 2: BUILD
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "SETUP" ]
}

@test "flexible_headers: bare colon 'Phase 1: Setup' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
Phase 1: Setup
Create setup.

Phase 2: Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]
}

@test "flexible_headers: bare lowercase 'phase 1: Setup' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
phase 1: Setup
Create setup.

phase 2: Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]
}

@test "flexible_headers: bare hyphen 'Phase 1 - Setup' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
Phase 1 - Setup
Create setup.

Phase 2 - Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]
}

@test "flexible_headers: hashed space-only '# Phase 1 Setup' parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Phase 1 Setup
Create setup.

# Phase 2 Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]
}

@test "flexible_headers: bare no-title 'Phase 1' defaults title to 'Phase 1'" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
Phase 1
Create setup.

Phase 2
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Phase 1" ]
}

@test "flexible_headers: hashed no-title '## Phase 1' defaults title to 'Phase 1'" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1
Create setup.

## Phase 2
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Phase 1" ]
}

@test "flexible_headers: 'Phase 2 will follow next.' in description not treated as header" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Some content here.
Phase 2 will follow next.

## Phase 2: Build
Build it.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "flexible_headers: mixed formats in one file all parsed correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Phase 1: Alpha
Content 1.

## Phase 2: Beta
Content 2.

### Phase 3: Gamma
Content 3.

Phase 4: Delta
Content 4.

Phase 5 - Epsilon
Content 5.

Phase 6
Content 6.

## PHASE 7: Zeta
Content 7.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]

  run get_phase_title 1
  [ "$output" = "Alpha" ]

  run get_phase_title 2
  [ "$output" = "Beta" ]

  run get_phase_title 3
  [ "$output" = "Gamma" ]

  run get_phase_title 4
  [ "$output" = "Delta" ]

  run get_phase_title 5
  [ "$output" = "Epsilon" ]

  run get_phase_title 6
  [ "$output" = "Phase 6" ]

  run get_phase_title 7
  [ "$output" = "Zeta" ]
}

@test "parse_plan: returns error for missing file" {
  run parse_plan "$TEST_DIR/nonexistent.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "parse_plan: returns error for file with no phases" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Just a title
Some random content with no phase headers.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No phases found"* ]]
}

@test "phase_to_var: converts dot to underscore" {
  run phase_to_var "2.5"
  [ "$status" -eq 0 ]
  [ "$output" = "2_5" ]
}

@test "phase_to_var: integer unchanged" {
  run phase_to_var "3"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "phase_less_than: 2.5 < 3 returns 0" {
  run phase_less_than 2.5 3
  [ "$status" -eq 0 ]
}

@test "phase_less_than: 3 < 2.5 returns 1" {
  run phase_less_than 3 2.5
  [ "$status" -eq 1 ]
}

@test "phase_less_than: 2.5 < 2.15 is false (float comparison)" {
  run phase_less_than 2.5 2.15
  [ "$status" -eq 1 ]
}

@test "parse_plan: strips trailing whitespace from phase title" {
  # Write the plan with explicit trailing spaces on title lines
  printf '## Phase 1: Setup   \nCreate setup.\n\n## Phase 2: Build   \nBuild it.\n' > "$TEST_DIR/PLAN.md"

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup" ]

  run get_phase_title 2
  [ "$status" -eq 0 ]
  [ "$output" = "Build" ]
}

@test "parse_plan: dependency line with extra numbers in comment ignores them" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
First phase

## Phase 2: Build
**Depends on:** Phase 1 (see section 3 for details)

Second phase

## Phase 3: Deploy
Third phase
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_dependencies 2
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "get_all_phases: returns decimal phases line by line" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2.5: Hotfix
Do hotfix.

## Phase 3: Finalize
Wrap up.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_all_phases
  [ "$status" -eq 0 ]
  # Output should contain each phase on its own line
  echo "$output" | grep -q "^1$"
  echo "$output" | grep -q "^2.5$"
  echo "$output" | grep -q "^3$"
}
