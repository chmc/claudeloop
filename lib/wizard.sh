#!/bin/sh

# Setup and Configuration Wizards
# Interactive prompts for first-run setup and recovery configuration

# Convert true/false to y/n for display in wizard prompts
bool_yn() { if [ "$1" = "true" ]; then printf 'y'; else printf 'n'; fi; }

# Interactive first-run wizard. Prompts for each configurable setting.
# Only runs when: no .claudeloop.conf, stdin is a tty (or _WIZARD_FORCE=1), not --dry-run.
# Mutates globals directly; write_config() persists them immediately after.
run_setup_wizard() {
  local conf_file=".claudeloop/.claudeloop.conf"
  [ -f "$conf_file" ] && return 0
  $DRY_RUN && return 0
  [ -z "$_WIZARD_FORCE" ] && ! [ -t 0 ] && return 0
  [ -z "$_WIZARD_FORCE" ] && [ "$YES_MODE" = "true" ] && return 0

  local response

  # Returning user: defaults already loaded via apply_config_precedence
  if [ -d ".claudeloop/archive" ]; then
    printf '\nPrevious run archived. Run setup wizard to change settings? [y/N] '
    read -r response || return 0
    case "$response" in
      [Yy]) ;;  # fall through to full wizard below
      *)
        write_config
        return 0 ;;
    esac
  fi

  printf '\nWelcome to claudeloop! Let'"'"'s configure your project.\n'
  printf 'Press Enter to accept the default [shown in brackets].\n\n'

  # PLAN_FILE
  if [ -n "$_CLI_PLAN_FILE" ]; then
    printf 'Plan file: using --plan %s\n' "$PLAN_FILE"
  else
    printf 'Plan file [%s]: ' "$PLAN_FILE"
    read -r response || return 0
    [ -n "$response" ] && PLAN_FILE="$response"
  fi

  # PROGRESS_FILE
  if [ -n "$_CLI_PROGRESS_FILE" ]; then
    printf 'Progress file: using --progress %s\n' "$PROGRESS_FILE"
  else
    printf 'Progress file [%s]: ' "$PROGRESS_FILE"
    read -r response || return 0
    [ -n "$response" ] && PROGRESS_FILE="$response"
  fi

  # MAX_RETRIES
  if [ -n "$_CLI_MAX_RETRIES" ]; then
    printf 'Max retries: using --max-retries %s\n' "$MAX_RETRIES"
  else
    printf 'Max retries on failure [%s]: ' "$MAX_RETRIES"
    read -r response || return 0
    if [ -n "$response" ]; then
      case "$response" in
        *[!0-9]*) ;;             # non-digit chars: keep default
        *) MAX_RETRIES="$response" ;;
      esac
    fi
  fi

  # QUOTA_RETRY_INTERVAL
  if [ -n "$_CLI_QUOTA_RETRY_INTERVAL" ]; then
    printf 'Quota retry interval: using --quota-retry-interval %s\n' "$QUOTA_RETRY_INTERVAL"
  else
    printf 'Quota wait after API limit, seconds [%s]: ' "$QUOTA_RETRY_INTERVAL"
    read -r response || return 0
    if [ -n "$response" ]; then
      case "$response" in
        *[!0-9]*) ;;             # non-digit chars: keep default
        *) QUOTA_RETRY_INTERVAL="$response" ;;
      esac
    fi
  fi

  # SIMPLE_MODE
  if [ -n "$_CLI_SIMPLE_MODE" ]; then
    printf 'Simple mode: using --simple\n'
  else
    printf 'Simple output, no colors? (y/n) [%s]: ' "$(bool_yn "$SIMPLE_MODE")"
    read -r response || return 0
    case "$response" in
      [Yy]|[Yy][Ee][Ss]) SIMPLE_MODE=true ;;
      [Nn]|[Nn][Oo]) SIMPLE_MODE=false ;;
    esac
  fi

  # SKIP_PERMISSIONS
  if [ -n "$_CLI_SKIP_PERMISSIONS" ]; then
    printf 'Skip permissions: using --dangerously-skip-permissions\n'
  else
    printf 'Dangerously skip permissions? (y/n) [%s]: ' "$(bool_yn "$SKIP_PERMISSIONS")"
    read -r response || return 0
    case "$response" in
      [Yy]|[Yy][Ee][Ss]) SKIP_PERMISSIONS=true ;;
      [Nn]|[Nn][Oo]) SKIP_PERMISSIONS=false ;;
    esac
  fi

  # PHASE_PROMPT_FILE
  if [ -n "$_CLI_PHASE_PROMPT_FILE" ]; then
    printf 'Phase prompt: using --phase-prompt %s\n' "$PHASE_PROMPT_FILE"
  else
    local prompt_default="${PHASE_PROMPT_FILE:-none}"
    printf 'Phase prompt template file [%s]: ' "$prompt_default"
    read -r response || return 0
    [ -n "$response" ] && [ "$response" != "none" ] && PHASE_PROMPT_FILE="$response"
  fi

  # AI_PARSE
  if [ -n "$_CLI_AI_PARSE" ]; then
    printf 'AI parsing: using --ai-parse\n'
  else
    printf 'AI-parse free-form plans? (y/n) [%s]: ' "$(bool_yn "$AI_PARSE")"
    read -r response || return 0
    case "$response" in
      [Yy]|[Yy][Ee][Ss]) AI_PARSE=true ;;
      [Nn]|[Nn][Oo]) AI_PARSE=false ;;
    esac
  fi

  # GRANULARITY (only ask if AI_PARSE is true)
  if [ "$AI_PARSE" = "true" ]; then
    if [ -n "$_CLI_GRANULARITY" ]; then
      printf 'Granularity: using --granularity %s\n' "$GRANULARITY"
    else
      printf 'AI breakdown depth (phases/tasks/steps) [%s]: ' "$GRANULARITY"
      read -r response || return 0
      case "$response" in
        phases|tasks|steps) GRANULARITY="$response" ;;
      esac
    fi
  fi

  # VERIFY_PHASES
  if [ -n "$_CLI_VERIFY_PHASES" ]; then
    printf 'Verify phases: using --verify\n'
  else
    printf 'Verify phases with fresh AI? (y/n) [%s]: ' "$(bool_yn "$VERIFY_PHASES")"
    read -r response || return 0
    case "$response" in
      [Yy]|[Yy][Ee][Ss]) VERIFY_PHASES=true ;;
      [Nn]|[Nn][Oo]) VERIFY_PHASES=false ;;
    esac
  fi

  # REFACTOR_PHASES
  if [ -n "$_CLI_REFACTOR_PHASES" ]; then
    printf 'Auto-refactor: using --refactor\n'
  else
    printf 'Auto-refactor after each phase? (y/n) [y]: '
    read -r response || return 0
    case "$response" in
      [Nn]|[Nn][Oo]) REFACTOR_PHASES=false ;;
      *) REFACTOR_PHASES=true ;;
    esac
  fi

  # .gitignore
  if ! grep -qF '.claudeloop' .gitignore 2>/dev/null; then
    if [ ! -f ".gitignore" ]; then
      printf 'No .gitignore found. Create one with .claudeloop/? (Y/n) '
    else
      printf 'Add .claudeloop/ to .gitignore? (Y/n) '
    fi
    read -r response || return 0
    case "$response" in
      [Nn]) _GITIGNORE_APPROVED=false ;;
      *)
        _GITIGNORE_APPROVED=true
        if [ ! -f ".gitignore" ]; then
          printf '# claudeloop runtime\n.claudeloop/\n' > .gitignore
        else
          printf '\n# claudeloop runtime\n.claudeloop/\n' >> .gitignore
        fi
        _add_platform_gitignore silent
        ;;
    esac
  fi

  printf '\n'
}

# Re-configure runtime settings after recovery. Skips file paths and AI parsing
# since those are determined by the recovery process.
# Respects _CLI_* flags (same pattern as run_setup_wizard).
run_config_wizard() {
  printf '\nRecovery changed your execution plan. Let'"'"'s verify runtime settings.\n'
  printf 'Press Enter to keep the current value [shown in brackets].\n\n'
  local response

  # MAX_RETRIES
  if [ -n "$_CLI_MAX_RETRIES" ]; then
    printf 'Max retries: using --max-retries %s\n' "$MAX_RETRIES"
  else
    printf 'Max retries on failure [%s]: ' "$MAX_RETRIES"
    read -r response || return 0
    if [ -n "$response" ]; then
      case "$response" in *[!0-9]*) ;; *) MAX_RETRIES="$response" ;; esac
    fi
  fi

  # SKIP_PERMISSIONS
  if [ -n "$_CLI_SKIP_PERMISSIONS" ]; then
    printf 'Skip permissions: using --dangerously-skip-permissions\n'
  else
    printf 'Dangerously skip permissions? (y/n) [%s]: ' "$(bool_yn "$SKIP_PERMISSIONS")"
    read -r response || return 0
    case "$response" in
      [Yy]|[Yy][Ee][Ss]) SKIP_PERMISSIONS=true ;;
      [Nn]|[Nn][Oo]) SKIP_PERMISSIONS=false ;;
    esac
  fi

  # VERIFY_PHASES
  if [ -n "$_CLI_VERIFY_PHASES" ]; then
    printf 'Verify phases: using --verify\n'
  else
    printf 'Verify phases with fresh AI? (y/n) [%s]: ' "$(bool_yn "$VERIFY_PHASES")"
    read -r response || return 0
    case "$response" in
      [Yy]|[Yy][Ee][Ss]) VERIFY_PHASES=true ;;
      [Nn]|[Nn][Oo]) VERIFY_PHASES=false ;;
    esac
  fi

  # REFACTOR_PHASES
  if [ -n "$_CLI_REFACTOR_PHASES" ]; then
    printf 'Auto-refactor: using --refactor\n'
  else
    printf 'Auto-refactor after each phase? (y/n) [%s]: ' "$(bool_yn "$REFACTOR_PHASES")"
    read -r response || return 0
    case "$response" in
      [Yy]|[Yy][Ee][Ss]) REFACTOR_PHASES=true ;;
      [Nn]|[Nn][Oo]) REFACTOR_PHASES=false ;;
    esac
  fi

  printf '\n'
}
