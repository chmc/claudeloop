# Prompt Design

When building or modifying phase prompts in `lib/prompt.sh`:

- Inject compact metadata inline (phase indexes, summaries, status labels)
- For full content, use file references with imperative read instructions — never inject large text blocks into phase prompts
- Frame file references as mandatory first actions, not optional suggestions ("Before starting, read X" not "You may optionally read X")
