#!/bin/sh

# detect_long_blocks(threshold, files...)
# Reports code blocks (brace-delimited) exceeding threshold lines.
# Language-agnostic: works for JS, TS, Go, Java, C, Rust, shell, etc.
detect_long_blocks() {
  local _dlb_thresh="${1:-50}"; shift
  for _dlb_f in "$@"; do
    [ -f "$_dlb_f" ] || continue
    awk -v thresh="$_dlb_thresh" -v file="$_dlb_f" '
      /{/ {
        if (depth == 0) start = NR
        depth += gsub(/{/, "{")
      }
      /}/ {
        depth -= gsub(/}/, "}")
        if (depth <= 0 && start > 0) {
          len = NR - start + 1
          if (len > thresh) print file ":" start " (" len " lines)"
          depth = 0; start = 0
        }
      }
    ' "$_dlb_f"
  done 2>/dev/null | head -15
}

# detect_duplicates(min_lines, files...)
# Reports pairs of files with identical normalized 10-line chunks.
# Skips first 20 lines per file (imports/headers zone).
detect_duplicates() {
  local _dd_min="${1:-10}"; shift
  for _dd_f in "$@"; do
    [ -f "$_dd_f" ] || continue
    awk -v file="$_dd_f" -v min="$_dd_min" '
      NR > 20 {
        lines[NR % min] = $0
        if (NR >= 20 + min) {
          chunk = ""
          for (i = 0; i < min; i++) chunk = chunk lines[(NR - min + 1 + i) % min]
          gsub(/[[:space:]]/, "", chunk)
          if (length(chunk) > 50) print chunk, file, NR - min + 1
        }
      }
    ' "$_dd_f"
  done 2>/dev/null | sort | head -200 | awk '
    $1 == prev { print prev_loc " ~ " $2 ":" $3; prev = ""; next }
    { prev = $1; prev_loc = $2 ":" $3 }
  ' | head -10
}

# detect_nesting(threshold, files...)
# Reports lines with indent depth exceeding threshold (default 4 levels).
# Normalizes tabs via expand before measuring.
detect_nesting() {
  local _dn_thresh="${1:-4}"; shift
  for _dn_f in "$@"; do
    [ -f "$_dn_f" ] || continue
    expand "$_dn_f" 2>/dev/null | awk -v thresh="$_dn_thresh" -v file="$_dn_f" '
      /^[[:space:]]*$/ { next }
      {
        match($0, /^[[:space:]]*/)
        indent = int(RLENGTH / 2)
        if (indent > thresh) print file ":" NR " (depth " indent ")"
      }
    '
  done 2>/dev/null | head -10
}

# detect_fanout(threshold, files...)
# Reports files with more import/require/use statements than threshold (default 10).
detect_fanout() {
  local _df_thresh="${1:-10}"; shift
  for _df_f in "$@"; do
    [ -f "$_df_f" ] || continue
    local _df_imports _df_requires _df_count
    _df_imports=$(grep -cE '^[[:space:]]*(import|from|#include|use|mod)[[:space:](\"'"'"']' \
      "$_df_f" 2>/dev/null || true)
    _df_requires=$(grep -cE '\brequire[[:space:]]*\(' "$_df_f" 2>/dev/null || true)
    _df_count=$((_df_imports + _df_requires))
    if [ "$_df_count" -gt "$_df_thresh" ]; then
      printf '%s (%d imports)\n' "$_df_f" "$_df_count"
    fi
  done
}
