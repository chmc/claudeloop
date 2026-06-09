#!/bin/sh

# Configuration Management Library
# Handles config file loading, writing, and setup/config wizards

# $1: "silent" to skip prompting (used when patching an existing .gitignore)
_add_platform_gitignore() {
  local os silent
  silent="${1:-}"
  os=$(uname -s 2>/dev/null) || return 0
  case "$os" in
    Darwin)
      if [ "$silent" = "silent" ]; then
        printf '\n# macOS\n.DS_Store\n._*\n' >> .gitignore
      else
        if ! [ -t 0 ] || [ "$YES_MODE" = "true" ]; then
          response="y"
        else
          printf 'Add macOS-specific ignores (.DS_Store, ._*)? (Y/n) '
          read -r response || return 0
        fi
        case "$response" in
          [Nn]) ;;
          *) printf '\n# macOS\n.DS_Store\n._*\n' >> .gitignore ;;
        esac
      fi
      ;;
    MINGW*|CYGWIN*|MSYS*)
      if [ "$silent" = "silent" ]; then
        printf '\n# Windows\nThumbs.db\ndesktop.ini\n' >> .gitignore
      else
        if ! [ -t 0 ] || [ "$YES_MODE" = "true" ]; then
          response="y"
        else
          printf 'Add Windows-specific ignores (Thumbs.db, desktop.ini)? (Y/n) '
          read -r response || return 0
        fi
        case "$response" in
          [Nn]) ;;
          *) printf '\n# Windows\nThumbs.db\ndesktop.ini\n' >> .gitignore ;;
        esac
      fi
      ;;
  esac
}

# Load .claudeloop.conf key=value config file (do NOT source)
load_config() {
  local conf_file="${1:-.claudeloop/.claudeloop.conf}"
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
      VERIFY_IDLE_TIMEOUT)   VERIFY_IDLE_TIMEOUT="$value" ;;
      DEAD_TIMEOUT)          DEAD_TIMEOUT="$value" ;;
      AI_PARSE)              AI_PARSE="$value" ;;
      GRANULARITY)           GRANULARITY="$value" ;;
      VERIFY_PHASES)         VERIFY_PHASES="$value" ;;
      REFACTOR_PHASES)       REFACTOR_PHASES="$value" ;;
      REFACTOR_MAX_RETRIES) REFACTOR_MAX_RETRIES="$value" ;;
      PROVIDER)              PROVIDER="$value" ;;
      EFFORT_LEVEL)
        case "$value" in low|medium|high|xhigh|max) EFFORT_LEVEL="$value" ;; esac
        ;;
      MODEL)          MODEL="$value" ;;
      MODEL_VERIFY)   MODEL_VERIFY="$value" ;;
    esac
  done < "$conf_file"
}

# Load config from the most recent archive's .claudeloop.conf
# Used as a fallback when the active conf was cleaned after archive
load_config_from_latest_archive() {
  [ -d ".claudeloop/archive" ] || return 0
  local _latest="" _dir
  for _dir in .claudeloop/archive/*/; do
    [ -d "$_dir" ] || continue
    _latest="$_dir"
  done
  [ -n "$_latest" ] || return 0
  [ -f "${_latest}.claudeloop.conf" ] || return 0
  load_config "${_latest}.claudeloop.conf"
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
  # (fallback for non-interactive / --yes mode where wizard was skipped)
  if [ "$_GITIGNORE_APPROVED" != "false" ] && ! grep -qF '.claudeloop' .gitignore 2>/dev/null; then
    if [ -f ".gitignore" ]; then
      printf '\n# claudeloop runtime\n.claudeloop/\n' >> .gitignore
    else
      printf '# claudeloop runtime\n.claudeloop/\n' > .gitignore
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
      printf 'VERIFY_IDLE_TIMEOUT=%s\n' "$VERIFY_IDLE_TIMEOUT"
      printf 'DEAD_TIMEOUT=%s\n'       "$DEAD_TIMEOUT"
      printf 'AI_PARSE=%s\n'          "$AI_PARSE"
      printf 'GRANULARITY=%s\n'       "$GRANULARITY"
      printf 'VERIFY_PHASES=%s\n'   "$VERIFY_PHASES"
      printf 'REFACTOR_PHASES=%s\n' "$REFACTOR_PHASES"
      printf 'REFACTOR_MAX_RETRIES=%s\n' "$REFACTOR_MAX_RETRIES"
      printf 'PROVIDER=%s\n'              "$PROVIDER"
      printf 'EFFORT_LEVEL=%s\n'          "$EFFORT_LEVEL"
      printf 'MODEL=%s\n'                "$MODEL"
      printf 'MODEL_VERIFY=%s\n'         "$MODEL_VERIFY"
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
  [ -n "$_CLI_VERIFY_IDLE_TIMEOUT" ] && update_conf_key "$conf_file" VERIFY_IDLE_TIMEOUT "$VERIFY_IDLE_TIMEOUT"
  [ -n "$_CLI_DEAD_TIMEOUT" ]        && update_conf_key "$conf_file" DEAD_TIMEOUT "$DEAD_TIMEOUT"
  [ -n "$_CLI_AI_PARSE" ]            && update_conf_key "$conf_file" AI_PARSE "$AI_PARSE"
  [ -n "$_CLI_GRANULARITY" ]         && update_conf_key "$conf_file" GRANULARITY "$GRANULARITY"
  [ -n "$_CLI_VERIFY_PHASES" ]       && update_conf_key "$conf_file" VERIFY_PHASES "$VERIFY_PHASES"
  [ -n "$_CLI_REFACTOR_PHASES" ]     && update_conf_key "$conf_file" REFACTOR_PHASES "$REFACTOR_PHASES"
  [ -n "$_CLI_REFACTOR_MAX_RETRIES" ] && update_conf_key "$conf_file" REFACTOR_MAX_RETRIES "$REFACTOR_MAX_RETRIES"
  [ -n "$_CLI_PROVIDER" ]            && update_conf_key "$conf_file" PROVIDER "$PROVIDER"
  [ -n "$_CLI_EFFORT_LEVEL" ]        && update_conf_key "$conf_file" EFFORT_LEVEL "$EFFORT_LEVEL"
  [ -n "$_CLI_MODEL" ]               && update_conf_key "$conf_file" MODEL "$MODEL"
  [ -n "$_CLI_MODEL_VERIFY" ]        && update_conf_key "$conf_file" MODEL_VERIFY "$MODEL_VERIFY"
  return 0
}

# commit_gitignore()
# Commits .gitignore if it has uncommitted changes (tracked or untracked).
# Uses pathspec (git commit .gitignore) to commit ONLY .gitignore,
# leaving any other staged files untouched.
# Non-fatal: logs warning on failure, always returns 0.
commit_gitignore() {
  [ -n "$(git status --porcelain .gitignore 2>/dev/null)" ] || return 0
  if ! git add .gitignore 2>/dev/null || \
     ! git commit -q .gitignore -m "chore: add .claudeloop/ to .gitignore" 2>/dev/null; then
    print_warning "Could not auto-commit .gitignore"
  fi
  return 0
}

