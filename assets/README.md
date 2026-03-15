# Assets

Visual assets for the ClaudeLoop README.

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
gifsicle --optimize=3 --lossy=80 -o assets/demo-execution.gif assets/demo-execution.gif
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
| `setup-demo-todos.sh` | Prepares temp environment for todo demo |
| `setup-demo-verify.sh` | Prepares temp environment for verify demo |
| `setup-demo-refactor.sh` | Prepares temp environment for refactor demo |
| `fake-claude-todos` | Custom fake Claude with paced TodoWrite events |
| `fake-claude-verify` | Custom fake Claude for execution + verification |
| `fake-claude-refactor` | Custom fake Claude for exec + verify + refactor flow |
| `demo-execution-output/` | Fake Claude NDJSON responses per phase |
| `screenshot-startup.png` | Static screenshot: startup + phase list |
| `screenshot-completion.png` | Static screenshot: all phases complete |
