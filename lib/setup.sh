#!/bin/sh

# Setup and Environment Validation
# Validates git repository, uncommitted changes, and provider availability

# Validate environment
validate_environment() {
  # Check if in git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository. ClaudeLoop requires git for safety."
    if ! [ -t 0 ] || [ "$YES_MODE" = "true" ]; then
      response="y"
    else
      printf 'Initialize a git repository here? (Y/n) '
      read -r response
    fi
    case "$response" in
      [Nn])
        echo "Aborted."
        exit 1
        ;;
      *)
        git init .
        print_success "Initialized git repository"
        ;;
    esac
  fi

  # Check for uncommitted changes
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    if [ "$RESUME_MODE" = "true" ]; then
      print_warning "Uncommitted changes detected (resuming existing session)."
      # Continue without prompting — changes are from prior session
    elif [ -t 0 ] && [ "$YES_MODE" = "false" ]; then
      print_warning "Uncommitted changes detected. Consider committing before starting."
      printf 'Continue anyway? (y/N) '
      read -r response
      case "$response" in
        [Yy]) ;;
        *) echo "Aborted."; exit 0 ;;
      esac
    elif [ "$YES_MODE" = "true" ]; then
      : # continue — unattended mode
    else
      print_error "Uncommitted changes detected. Use --yes to proceed non-interactively."
      exit 1
    fi
  fi

  # Detect provider
  if ! _provider=$(provider_detect); then
    exit 1
  fi
  log_verbose "Provider: $_provider"

  # Check if provider CLI is available
  if ! command -v "$(provider_cli)" > /dev/null 2>&1; then
    print_error "$(provider_cli) CLI not found. Please install it first."
    exit 1
  fi

}
