#!/bin/sh

# Configuration Management Library
# Handles config file loading, writing, and setup/config wizards

# Load .claudeloop.conf key=value config file (do NOT source)
load_config() {
  local conf_file=".claudeloop/.claudeloop.conf"
  [ ! -f "$conf_file" ] && return 0

  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    key=$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$key" in
      PLAN_FILE)         PLAN_FILE="$value" ;;
      PROGRESS_FILE)     PROGRESS_FILE="$value" ;;
      MAX_RETRIES)       MAX_RETRIES="$value" ;;
      SIMPLE_MODE)       SIMPLE_MODE="$value" ;;
      PHASE_PROMPT_FILE) PHASE_PROMPT_FILE="$value" ;;
      BASE_DELAY)             BASE_DELAY="$value" ;;
      QUOTA_RETRY_INTERVAL)   QUOTA_RETRY_INTERVAL="$value" ;;
      SKIP_PERMISSIONS)       SKIP_PERMISSIONS="$value" ;;
      STREAM_TRUNCATE_LEN)    STREAM_TRUNCATE_LEN="$value" ;;
      HOOKS_ENABLED)          HOOKS_ENABLED="$value" ;;
      MAX_PHASE_TIME)         MAX_PHASE_TIME="$value" ;;
      IDLE_TIMEOUT)           IDLE_TIMEOUT="$value" ;;
      VERIFY_TIMEOUT)        VERIFY_TIMEOUT="$value" ;;
      AI_PARSE)              AI_PARSE="$value" ;;
      GRANULARITY)           GRANULARITY="$value" ;;
      VERIFY_PHASES)         VERIFY_PHASES="$value" ;;
      REFACTOR_PHASES)       REFACTOR_PHASES="$value" ;;
    esac
  done < "$conf_file"
}

# Replace or append a key=value line in the conf file (POSIX, no sed -i)
# Values containing sed metacharacters (&, \, |) are escaped before substitution.
update_conf_key() {
  local file="$1" key="$2" value="$3" tmp escaped
  tmp="${file}.tmp"
  escaped=$(printf '%s\n' "$value" | sed 's/[\\&|]/\\&/g')
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed "s|^${key}=.*|${key}=${escaped}|" "$file" > "$tmp" && mv "$tmp" "$file"
    # Ensure trailing newline (defense-in-depth for load_config)
    [ -n "$(tail -c 1 "$file")" ] && printf '\n' >> "$file" || true
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

# Create or update .claudeloop.conf after arg parsing
write_config() {
  local conf_file=".claudeloop/.claudeloop.conf"

  # Never write config during dry-run
  $DRY_RUN && return 0

  # Ensure .claudeloop/ is gitignored before creating the directory
  if ! grep -qF '.claudeloop' .gitignore 2>/dev/null; then
    if [ -f ".gitignore" ]; then
      printf '\n.claudeloop/\n' >> .gitignore
    else
      printf '.claudeloop/\n' > .gitignore
    fi
  fi

  mkdir -p ".claudeloop"

  if [ ! -f "$conf_file" ]; then
    # First run: create conf with all current persistable settings
    {
      printf '# claudeloop configuration — edit or delete freely\n'
      printf 'PLAN_FILE=%s\n'        "$PLAN_FILE"
      printf 'PROGRESS_FILE=%s\n'    "$PROGRESS_FILE"
      printf 'MAX_RETRIES=%s\n'      "$MAX_RETRIES"
      printf 'SIMPLE_MODE=%s\n'      "$SIMPLE_MODE"
      printf 'SKIP_PERMISSIONS=%s\n' "$SKIP_PERMISSIONS"
      printf 'BASE_DELAY=%s\n'       "$BASE_DELAY"
      printf 'STREAM_TRUNCATE_LEN=%s\n' "$STREAM_TRUNCATE_LEN"
      printf 'MAX_PHASE_TIME=%s\n'      "$MAX_PHASE_TIME"
      printf 'IDLE_TIMEOUT=%s\n'       "$IDLE_TIMEOUT"
      printf 'VERIFY_TIMEOUT=%s\n'   "$VERIFY_TIMEOUT"
      printf 'AI_PARSE=%s\n'          "$AI_PARSE"
      printf 'GRANULARITY=%s\n'       "$GRANULARITY"
      printf 'VERIFY_PHASES=%s\n'   "$VERIFY_PHASES"
      printf 'REFACTOR_PHASES=%s\n' "$REFACTOR_PHASES"
      [ -n "$PHASE_PROMPT_FILE" ]    && printf 'PHASE_PROMPT_FILE=%s\n'    "$PHASE_PROMPT_FILE"
      [ -n "$QUOTA_RETRY_INTERVAL" ] && printf 'QUOTA_RETRY_INTERVAL=%s\n' "$QUOTA_RETRY_INTERVAL"
    } > "$conf_file"
    print_success "Created .claudeloop/.claudeloop.conf"
    return 0
  fi

  # Existing conf: update only CLI-set keys
  [ -n "$_CLI_PLAN_FILE" ]            && update_conf_key "$conf_file" PLAN_FILE "$PLAN_FILE"
  [ -n "$_CLI_PROGRESS_FILE" ]        && update_conf_key "$conf_file" PROGRESS_FILE "$PROGRESS_FILE"
  [ -n "$_CLI_MAX_RETRIES" ]          && update_conf_key "$conf_file" MAX_RETRIES "$MAX_RETRIES"
  [ -n "$_CLI_SIMPLE_MODE" ]          && update_conf_key "$conf_file" SIMPLE_MODE "$SIMPLE_MODE"
  [ -n "$_CLI_PHASE_PROMPT_FILE" ]    && update_conf_key "$conf_file" PHASE_PROMPT_FILE "$PHASE_PROMPT_FILE"
  [ -n "$_CLI_QUOTA_RETRY_INTERVAL" ] && update_conf_key "$conf_file" QUOTA_RETRY_INTERVAL "$QUOTA_RETRY_INTERVAL"
  [ -n "$_CLI_SKIP_PERMISSIONS" ]     && update_conf_key "$conf_file" SKIP_PERMISSIONS "$SKIP_PERMISSIONS"
  [ -n "$_CLI_MAX_PHASE_TIME" ]       && update_conf_key "$conf_file" MAX_PHASE_TIME "$MAX_PHASE_TIME"
  [ -n "$_CLI_IDLE_TIMEOUT" ]        && update_conf_key "$conf_file" IDLE_TIMEOUT "$IDLE_TIMEOUT"
  [ -n "$_CLI_VERIFY_TIMEOUT" ]     && update_conf_key "$conf_file" VERIFY_TIMEOUT "$VERIFY_TIMEOUT"
  [ -n "$_CLI_AI_PARSE" ]            && update_conf_key "$conf_file" AI_PARSE "$AI_PARSE"
  [ -n "$_CLI_GRANULARITY" ]         && update_conf_key "$conf_file" GRANULARITY "$GRANULARITY"
  [ -n "$_CLI_VERIFY_PHASES" ]       && update_conf_key "$conf_file" VERIFY_PHASES "$VERIFY_PHASES"
  [ -n "$_CLI_REFACTOR_PHASES" ]     && update_conf_key "$conf_file" REFACTOR_PHASES "$REFACTOR_PHASES"
  return 0
}

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

  printf '\nWelcome to claudeloop! Let'"'"'s configure your project.\n'
  printf 'Press Enter to accept the default [shown in brackets].\n\n'

  local response

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
