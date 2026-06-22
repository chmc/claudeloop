#!/bin/sh
# Nudge: user-injected guidance for stuck phases.
# Storage: .claudeloop/nudge-phase-{N}.md — plain text, survives restart.

nudge_file_path() {
  printf '.claudeloop/nudge-phase-%s.md' "$1"
}

read_nudge() {
  local _rn_path
  _rn_path=$(nudge_file_path "$1")
  [ -s "$_rn_path" ] && cat "$_rn_path" || true
}

clear_nudge() {
  rm -f "$(nudge_file_path "$1")"
}

# Save nudge text to file and log to live log. Testable without /dev/tty.
_nudge_save_text() {
  local _nst_phase="$1" _nst_text="$2" _nst_path _nst_preview
  _nst_path=$(nudge_file_path "$_nst_phase")
  printf '%s\n' "$_nst_text" > "$_nst_path"
  _nst_preview=$(printf '%s' "$_nst_text" | head -c 80)
  printf '\033[32mNudge saved:\033[0m %s\n' "$_nst_preview" >&2
  log_live "Nudge saved: $_nst_preview"
}

# Prompt user for nudge text. Prints transition header, reads input, saves file.
# Returns 0 if nudge saved, 1 if skipped (empty input).
prompt_nudge_text() {
  local _pnt_phase="$1"
  local _pnt_text _pnt_path _pnt_editor

  printf '\n\033[33m\xe2\x8f\xb8 Stopped phase %s.\033[0m Enter guidance for next attempt:\n' "$_pnt_phase" >&2
  printf '(Ctrl+U to clear, empty to skip, '"'"'e'"'"' for editor)\n' >&2
  printf '\033[2mnudge>\033[0m ' >&2

  IFS= read -r _pnt_text < /dev/tty

  if [ "$_pnt_text" = "e" ] || [ "$_pnt_text" = "E" ]; then
    _pnt_path=$(nudge_file_path "$_pnt_phase")
    _pnt_editor="${EDITOR:-vi}"
    if ! command -v "$_pnt_editor" >/dev/null 2>&1; then
      _pnt_editor="vi"
    fi
    "$_pnt_editor" "$_pnt_path" < /dev/tty > /dev/tty 2>&1
    if [ -s "$_pnt_path" ]; then
      _pnt_text=$(cat "$_pnt_path")
      printf '\033[32mNudge saved (editor).\033[0m\n' >&2
      log_live "Nudge saved (editor)."
      return 0
    else
      printf 'No nudge — retrying without guidance.\n' >&2
      rm -f "$_pnt_path"
      return 1
    fi
  fi

  if [ -z "$_pnt_text" ]; then
    printf 'No nudge — retrying without guidance.\n' >&2
    return 1
  fi

  _nudge_save_text "$_pnt_phase" "$_pnt_text"
  return 0
}
