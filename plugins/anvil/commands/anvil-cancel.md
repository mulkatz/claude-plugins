---
description: 'Cancel an active Anvil debate'
allowed-tools:
  [
    'Bash(test -f .claude/anvil-state.local.md:*)',
    'Bash(rm .claude/anvil-state.local.md)',
    'Read(.claude/anvil-state.local.md)',
  ]
hide-from-slash-command-tool: 'true'
---

# Cancel Anvil

To cancel the active debate:

1. Check if `.claude/anvil-state.local.md` exists using Bash:
   `test -f .claude/anvil-state.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active Anvil debate to cancel."

3. **If EXISTS**:
   - Read `.claude/anvil-state.local.md` to get the current round, phase, and question
   - Remove the file using Bash: `rm .claude/anvil-state.local.md`
   - Report: "Cancelled Anvil debate: '[question]' (was at round N, phase: [phase])"
