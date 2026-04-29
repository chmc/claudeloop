#!/bin/sh

# args.sh - Command-line argument parsing for claudeloop
# Requires: VERSION (set before sourcing), lib/ui.sh (for print_logo)

# Usage information
usage() {
  print_logo
  cat << EOF
ClaudeLoop - Phase-by-Phase Execution Tool

Usage: $(basename "$0") [OPTIONS]

Options:
  --plan <file>          Plan file to execute (default: PLAN.md)
  --progress <file>      Progress file (default: PROGRESS.md)
  --reset                Clear all run state and start fresh
  --continue             Continue from last checkpoint (default)
  --phase <n>            Start from specific phase number
  --mark-complete <n>    Mark a phase as completed (use after a phase was done but logged as failed)
  --recover-progress     Reconstruct PROGRESS.md from .claudeloop/logs/ (use after progress corruption)
  --dry-run              Validate plan without execution
  --phase-prompt <file>  Custom prompt template for phase execution
  --max-retries <n>      Maximum retry attempts per phase (default: 10)
  --quota-retry-interval <s>  Seconds to wait after quota limit error (default: 900)
  --max-phase-time <s>   Kill claude after N seconds per phase, then retry (0=disabled, default)
  --idle-timeout <s>     Exit stream processor after N seconds of no activity (default: 600, 0=disabled)
  --dead-timeout <s>     Exit if only heartbeats for N seconds (no real events, default: 180, 0=disabled)
  --verify-timeout <s>   Kill verification after N seconds (default: 300)
  --simple               Use simple output mode (no colors/fancy UI)
  --verbose              Enable verbose debug output
  --force                Kill any running instance and take over (preserves progress)
  --yes, -y              Non-interactive mode: auto-answer all prompts
                         (enabled automatically when running inside Claude Code)
  --ai-parse             Use AI to decompose plan into granular phases
  --granularity <level>  Breakdown depth: phases, tasks, steps (default: tasks)
  --no-retry             Skip interactive retry loop during AI parse (exit 2 on verify fail)
  --ai-parse-feedback    Reparse using feedback from previous verification failure
  --verify               Verify each phase with a fresh read-only Claude instance
                         (doubles API calls per phase)
  --refactor             Auto-refactor code after each phase completion
                         (up to 4 API calls per phase with --verify)
  --refactor-max-retries <n>  Max refactor attempts per phase (default: 20)
  --dangerously-skip-permissions  Pass --dangerously-skip-permissions to claude
  --archive              Archive current run state, start fresh, and exit
  --list-archives        List archived runs and exit
  --restore <name>       Restore an archived run and exit
  --replay [archive]    Regenerate replay.html and exit (optionally for an archived run)
  --monitor              Follow live output of a running claudeloop instance
  --version, -V          Print version and exit
  --help                 Show this help message

Examples:
  $(basename "$0") --plan my_plan.md
  $(basename "$0") --reset
  $(basename "$0") --phase 3 --continue

EOF
}

# Parse command-line arguments
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --plan)
        if [ $# -lt 2 ]; then echo "Error: --plan requires an argument" >&2; exit 1; fi
        PLAN_FILE="$2"; _CLI_PLAN_FILE=1
        shift 2
        ;;
      --progress)
        if [ $# -lt 2 ]; then echo "Error: --progress requires an argument" >&2; exit 1; fi
        PROGRESS_FILE="$2"; _CLI_PROGRESS_FILE=1
        shift 2
        ;;
      --reset)
        RESET_PROGRESS=true
        shift
        ;;
      --continue)
        # Default behavior
        shift
        ;;
      --phase)
        if [ $# -lt 2 ]; then echo "Error: --phase requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9.]*)  echo "Error: --phase requires a number" >&2; exit 1 ;; esac
        START_PHASE="$2"
        shift 2
        ;;
      --mark-complete)
        if [ $# -lt 2 ]; then echo "Error: --mark-complete requires an argument" >&2; exit 1; fi
        MARK_COMPLETE_PHASE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --phase-prompt)
        if [ $# -lt 2 ]; then echo "Error: --phase-prompt requires an argument" >&2; exit 1; fi
        PHASE_PROMPT_FILE="$2"; _CLI_PHASE_PROMPT_FILE=1
        shift 2
        ;;
      --max-retries)
        if [ $# -lt 2 ]; then echo "Error: --max-retries requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --max-retries requires a number" >&2; exit 1 ;; esac
        MAX_RETRIES="$2"; _CLI_MAX_RETRIES=1
        shift 2
        ;;
      --quota-retry-interval)
        if [ $# -lt 2 ]; then echo "Error: --quota-retry-interval requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --quota-retry-interval requires a number" >&2; exit 1 ;; esac
        QUOTA_RETRY_INTERVAL="$2"; _CLI_QUOTA_RETRY_INTERVAL=1
        shift 2
        ;;
      --max-phase-time)
        if [ $# -lt 2 ]; then echo "Error: --max-phase-time requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --max-phase-time requires a number" >&2; exit 1 ;; esac
        MAX_PHASE_TIME="$2"; _CLI_MAX_PHASE_TIME=1
        shift 2
        ;;
      --idle-timeout)
        if [ $# -lt 2 ]; then echo "Error: --idle-timeout requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --idle-timeout requires a number" >&2; exit 1 ;; esac
        IDLE_TIMEOUT="$2"; _CLI_IDLE_TIMEOUT=1
        shift 2
        ;;
      --verify-timeout)
        if [ $# -lt 2 ]; then echo "Error: --verify-timeout requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --verify-timeout requires a number" >&2; exit 1 ;; esac
        VERIFY_TIMEOUT="$2"; _CLI_VERIFY_TIMEOUT=1
        shift 2
        ;;
      --verify-idle-timeout)
        if [ $# -lt 2 ]; then echo "Error: --verify-idle-timeout requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --verify-idle-timeout requires a number" >&2; exit 1 ;; esac
        VERIFY_IDLE_TIMEOUT="$2"; _CLI_VERIFY_IDLE_TIMEOUT=1
        shift 2
        ;;
      --dead-timeout)
        if [ $# -lt 2 ]; then echo "Error: --dead-timeout requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --dead-timeout requires a number" >&2; exit 1 ;; esac
        DEAD_TIMEOUT="$2"; _CLI_DEAD_TIMEOUT=1
        shift 2
        ;;
      --simple)
        SIMPLE_MODE=true; _CLI_SIMPLE_MODE=1
        shift
        ;;
      --verbose)
        VERBOSE_MODE=true
        shift
        ;;
      --force)
        FORCE_MODE=true
        shift
        ;;
      --yes|-y)
        YES_MODE=true
        shift
        ;;
      --dangerously-skip-permissions)
        SKIP_PERMISSIONS=true; _CLI_SKIP_PERMISSIONS=1
        shift
        ;;
      --version|-V)
        printf '%s\n' "$VERSION"
        exit 0
        ;;
      --ai-parse)
        AI_PARSE=true; _CLI_AI_PARSE=1
        shift
        ;;
      --granularity)
        if [ $# -lt 2 ]; then echo "Error: --granularity requires an argument" >&2; exit 1; fi
        GRANULARITY="$2"; _CLI_GRANULARITY=1
        shift 2
        ;;
      --no-retry)
        NO_RETRY=true; _CLI_NO_RETRY=1
        shift
        ;;
      --ai-parse-feedback)
        AI_PARSE_FEEDBACK=true; _CLI_AI_PARSE_FEEDBACK=1
        shift
        ;;
      --verify)
        VERIFY_PHASES=true; _CLI_VERIFY_PHASES=1
        shift
        ;;
      --refactor)
        REFACTOR_PHASES=true; _CLI_REFACTOR_PHASES=1
        shift
        ;;
      --refactor-max-retries)
        if [ $# -lt 2 ]; then echo "Error: --refactor-max-retries requires an argument" >&2; exit 1; fi
        case "$2" in ''|*[!0-9]*) echo "Error: --refactor-max-retries requires a number" >&2; exit 1 ;; esac
        REFACTOR_MAX_RETRIES="$2"; _CLI_REFACTOR_MAX_RETRIES=1
        shift 2
        ;;
      --recover-progress)
        RECOVER_PROGRESS=true
        shift
        ;;
      --archive)
        ARCHIVE_MODE=true
        shift
        ;;
      --list-archives)
        LIST_ARCHIVES=true
        shift
        ;;
      --restore)
        if [ $# -lt 2 ]; then echo "Error: --restore requires an argument" >&2; exit 1; fi
        RESTORE_ARCHIVE="$2"
        shift 2
        ;;
      --replay)
        REPLAY_MODE=true
        # Optional archive name argument (next arg that doesn't start with --)
        if [ $# -ge 2 ] && case "$2" in --*) false;; *) true;; esac; then
          REPLAY_ARCHIVE="$2"
          shift
        fi
        shift
        ;;
      --monitor)
        MONITOR_MODE=true
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Error: Unknown option $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}
