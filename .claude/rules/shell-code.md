---
paths:
  - "lib/**/*.sh"
  - "claudeloop"
  - "install.sh"
  - "uninstall.sh"
---

# Shell Code Conventions

## POSIX strictures — forbidden bashisms

- No `[[ ]]` — use `[ ]` or `case`
- No arrays (`arr=(...)`, `${arr[@]}`) — use positional params or eval-named vars
- No `declare`, `typeset`, `nameref`
- No process substitution `<(...)` or `>(...)` — use temp files
- No `$'...'` ANSI-C quoting
- `local` is the one allowed bashism (SC3043 — supported by dash/ash/bash)

## Quoting

- Double-quote all expansions: `"$var"`, `"$(cmd)"`, `"${var:-default}"`
- Exception: intentional word-splitting or glob expansion

## Output

- `printf '%s\n' "$data"` for variable content that could start with `-`
- `echo "Error: ..."  >&2` is fine for fixed error strings

## Error handling

- `set -eu` in executable scripts (`claudeloop`, `install.sh`) — never at file scope in lib files
- Lib files are sourced by callers that control their own error mode

## Variable naming

- Per-function collision-avoidance prefix: `_funcabbrev_varname`
  - e.g. `update_fail_reason` → `_ufr_phase`, `_ufr_reason` (see `lib/execution.sh`)
- Module-scoped globals: `UPPER_CASE` (e.g. `MAX_RETRIES`, `BASE_DELAY`)
- Apply prefix convention in new code even where older functions are inconsistent

## ShellCheck

```sh
shellcheck -s sh -e SC3043 <file>
```

SC3043 suppresses the `local` warning intentionally. All other warnings apply.
