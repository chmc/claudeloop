# Contributing to claudeloop

## Token Optimization (Optional)

Reduce Claude Code API costs by 50-70% using [Tamp](https://github.com/sliday/tamp), a token compression proxy.

### Setup

```bash
# 1. Add Sliday plugin marketplace
claude plugin marketplace add sliday/claude-plugins

# 2. Install Tamp plugin (auto-starts on session start)
claude plugin install tamp@sliday

# 3. Add to ~/.zshrc (required for subagent support)
echo 'export ANTHROPIC_BASE_URL=http://localhost:7778' >> ~/.zshrc
source ~/.zshrc
```

The plugin auto-starts Tamp when you launch Claude Code. No manual startup needed.

### Verify

```bash
curl -s http://localhost:7778/health | jq .status
# Should output: "ok"
```
