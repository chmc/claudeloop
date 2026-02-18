#!/bin/sh
# Build phase prompt from template file.
# Supports {{PHASE_NUM}}, {{PHASE_TITLE}}, {{PHASE_DESCRIPTION}}, {{PLAN_FILE}}.
# If no {{}} placeholders found, appends a phase data section instead.

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
