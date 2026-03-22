# Assets

Visual assets for the ClaudeLoop README.

## When to regenerate

Regenerate **all** GIFs and screenshots when any of these change:
- `lib/ui.sh` — logo, headers, colors, phase icons
- `lib/stream_processor.sh` — spinner, tool formatting, todo/task panels
- `lib/execution.sh` — phase output structure
- `lib/verify.sh` / `lib/refactor.sh` — verification/refactor display
- `examples/PLAN.md.example` — dry-run demo content
- `assets/replay-template.html` — replay report UI (regenerate screenshots)

## Regenerating GIFs

Requires [VHS](https://github.com/charmbracelet/vhs) and [gifsicle](https://www.lcdf.org/gifsicle/):

```sh
brew install vhs gifsicle
```

### Dry-run demo

```sh
cd /path/to/claudeloop
vhs assets/demo-dryrun.tape
gifsicle --optimize=3 --lossy=80 -o assets/demo-dryrun.gif assets/demo-dryrun.gif
```

### Execution demo

```sh
cd /path/to/claudeloop
vhs assets/demo-execution.tape
gifsicle --optimize=3 --lossy=120 --colors 64 -o assets/demo-execution.gif assets/demo-execution.gif
```

### Todo tracking demo

```sh
cd /path/to/claudeloop
vhs assets/demo-todos.tape
gifsicle --optimize=3 --lossy=80 -o assets/demo-todos.gif assets/demo-todos.gif
```

### Verification demo

```sh
cd /path/to/claudeloop
vhs assets/demo-verify.tape
gifsicle --optimize=3 --lossy=80 -o assets/demo-verify.gif assets/demo-verify.gif
```

### Auto-refactor demo

```sh
cd /path/to/claudeloop
vhs assets/demo-refactor.tape
gifsicle --optimize=3 --lossy=80 -o assets/demo-refactor.gif assets/demo-refactor.gif
```

## Regenerating replay screenshots

Requires a `replay.html` file from a real or archived run:

```sh
node assets/capture-replay-screenshots.js path/to/replay.html
```

Outputs: `screenshot-replay.png`, `screenshot-replay-files.png`, `screenshot-replay-tools.png`, `screenshot-replay-timetravel.png`.

## Files

| File | Purpose |
|------|---------|
| `demo-dryrun.tape` | VHS tape for dry-run validation GIF |
| `demo-dryrun.gif` | Generated dry-run GIF |
| `demo-execution.tape` | VHS tape for phase execution GIF |
| `demo-execution.gif` | Generated execution GIF |
| `demo-todos.tape` | VHS tape for todo tracking GIF |
| `demo-todos.gif` | Generated todo tracking GIF |
| `demo-verify.tape` | VHS tape for verification GIF |
| `demo-verify.gif` | Generated verification GIF |
| `demo-refactor.tape` | VHS tape for auto-refactor GIF |
| `demo-refactor.gif` | Generated auto-refactor GIF |
| `setup-demo.sh` | Prepares temp environment for execution demo |
| `setup-demo-env.sh` | Sources setup-demo.sh for VHS tape (eval wrapper) |
| `setup-demo-todos.sh` | Prepares temp environment for todo demo |
| `setup-demo-verify.sh` | Prepares temp environment for verify demo |
| `setup-demo-refactor.sh` | Prepares temp environment for refactor demo |
| `fake-claude-todos` | Custom fake Claude with paced TodoWrite events |
| `fake-claude-verify` | Custom fake Claude for execution + verification |
| `fake-claude-refactor` | Custom fake Claude for exec + verify + refactor flow |
| `fake-claude-execution` | Custom fake Claude with paced output for execution demo |
| `screenshot-startup.png` | Static screenshot: startup + phase list |
| `screenshot-completion.png` | Static screenshot: all phases complete |
| `screenshot-replay.png` | Replay report: overview tab |
| `screenshot-replay-files.png` | Replay report: file impact view |
| `screenshot-replay-tools.png` | Replay report: phase detail with tool usage |
| `screenshot-replay-timetravel.png` | Replay report: time travel view |
| `capture-replay-screenshots.js` | Playwright script to regenerate replay screenshots |
