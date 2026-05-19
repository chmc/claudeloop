#!/usr/bin/env bats
# bats file_tags=refactor,detectors

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  . "$CLAUDELOOP_DIR/lib/detectors.sh"
}

# =============================================================================
# detect_long_blocks
# =============================================================================

@test "detect_long_blocks: reports block over threshold" {
  local f="$BATS_TEST_TMPDIR/big.js"
  printf 'function big() {\n' > "$f"
  for i in $(seq 1 55); do printf '  var x%s = %s;\n' "$i" "$i"; done >> "$f"
  printf '}\n' >> "$f"

  run detect_long_blocks 50 "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "big.js:1"
}

@test "detect_long_blocks: silent for block under threshold" {
  local f="$BATS_TEST_TMPDIR/small.js"
  printf 'function small() {\n' > "$f"
  for i in $(seq 1 20); do printf '  var x%s = %s;\n' "$i" "$i"; done >> "$f"
  printf '}\n' >> "$f"

  run detect_long_blocks 50 "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_long_blocks: handles nested braces correctly" {
  local f="$BATS_TEST_TMPDIR/nested.js"
  {
    printf 'function outer() {\n'
    printf '  if (true) {\n'
    for i in $(seq 1 60); do printf '    var x%s = %s;\n' "$i" "$i"; done
    printf '  }\n'
    printf '}\n'
  } > "$f"

  run detect_long_blocks 50 "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "nested.js:1"
}

@test "detect_long_blocks: graceful on missing file" {
  run detect_long_blocks 50 "/nonexistent/file.js"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# detect_duplicates
# =============================================================================

@test "detect_duplicates: reports identical 10-line chunks" {
  local chunk=""
  for i in $(seq 1 10); do chunk="${chunk}line_content_${i}\n"; done

  local f1="$BATS_TEST_TMPDIR/file1.sh"
  local f2="$BATS_TEST_TMPDIR/file2.sh"

  # Pad past 20-line skip zone
  for i in $(seq 1 25); do printf 'padding_%s\n' "$i"; done > "$f1"
  printf '%b' "$chunk" >> "$f1"
  for i in $(seq 1 25); do printf 'padding_%s\n' "$i"; done > "$f2"
  printf '%b' "$chunk" >> "$f2"

  run detect_duplicates 10 "$f1" "$f2"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "detect_duplicates: skips first 20 lines (imports zone)" {
  local chunk=""
  for i in $(seq 1 10); do chunk="${chunk}import_line_${i}\n"; done

  local f1="$BATS_TEST_TMPDIR/imp1.sh"
  local f2="$BATS_TEST_TMPDIR/imp2.sh"

  printf '%b' "$chunk" > "$f1"
  printf '%b' "$chunk" > "$f2"

  run detect_duplicates 10 "$f1" "$f2"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_duplicates: graceful on missing file" {
  run detect_duplicates 10 "/nonexistent/file.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# detect_nesting
# =============================================================================

@test "detect_nesting: reports lines over depth threshold" {
  local f="$BATS_TEST_TMPDIR/deep.sh"
  # 5 levels of 2-space indent = 10 spaces
  printf '          deeply_nested_code\n' > "$f"

  run detect_nesting 4 "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "deep.sh:1"
}

@test "detect_nesting: silent for lines under threshold" {
  local f="$BATS_TEST_TMPDIR/shallow.sh"
  printf '    shallow\n' > "$f"  # 2 levels

  run detect_nesting 4 "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_nesting: handles tabs via expand" {
  local f="$BATS_TEST_TMPDIR/tabbed.sh"
  # 5 tabs = 40 spaces via expand (depth > 4)
  printf '\t\t\t\t\ttab_indented\n' > "$f"

  run detect_nesting 4 "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "tabbed.sh:1"
}

@test "detect_nesting: skips blank lines" {
  local f="$BATS_TEST_TMPDIR/blanks.sh"
  printf '\n\n\n' > "$f"

  run detect_nesting 4 "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_nesting: graceful on missing file" {
  run detect_nesting 4 "/nonexistent/file.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# detect_fanout
# =============================================================================

@test "detect_fanout: reports file over import threshold" {
  local f="$BATS_TEST_TMPDIR/heavy.js"
  for i in $(seq 1 12); do printf 'import module%s from "mod%s"\n' "$i" "$i"; done > "$f"

  run detect_fanout 10 "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "heavy.js"
  echo "$output" | grep -q "12 imports"
}

@test "detect_fanout: silent for file under threshold" {
  local f="$BATS_TEST_TMPDIR/light.js"
  for i in $(seq 1 5); do printf 'import module%s from "mod%s"\n' "$i" "$i"; done > "$f"

  run detect_fanout 10 "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_fanout: counts require style" {
  local f="$BATS_TEST_TMPDIR/cjs.js"
  for i in $(seq 1 12); do printf 'const x%s = require("mod%s")\n' "$i" "$i"; done > "$f"

  run detect_fanout 10 "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "cjs.js"
}

@test "detect_fanout: counts python imports" {
  local f="$BATS_TEST_TMPDIR/module.py"
  for i in $(seq 1 12); do printf 'from module%s import thing%s\n' "$i" "$i"; done > "$f"

  run detect_fanout 10 "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "module.py"
}

@test "detect_fanout: graceful on missing file" {
  run detect_fanout 10 "/nonexistent/file.js"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
