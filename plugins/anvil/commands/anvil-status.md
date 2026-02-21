---
description: 'Show current Anvil debate status'
allowed-tools:
  ['Bash(test -f .claude/anvil-state.local.md:*)', 'Read(.claude/anvil-state.local.md)']
hide-from-slash-command-tool: 'true'
---

# Anvil Status

Check the current debate status:

1. Check if `.claude/anvil-state.local.md` exists using Bash:
   `test -f .claude/anvil-state.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active Anvil debate."

3. **If EXISTS**:
   - Read `.claude/anvil-state.local.md`
   - Report the following from the YAML frontmatter:
     - **Question**: the `question` field
     - **Mode**: the `mode` field
     - **Phase**: the `phase` field (advocate/critic/synthesizer)
     - **Round**: `round` of `max_rounds`
     - **Research**: the `research` field (true/false)
     - **Started**: the `started_at` field
