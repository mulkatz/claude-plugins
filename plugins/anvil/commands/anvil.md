---
description: 'Start an adversarial debate to stress-test an idea'
argument-hint:
  'QUESTION [--mode analyst|philosopher|devils-advocate|stakeholders] [--rounds N] [--position TEXT]
  [--research] [--framework adr|pre-mortem|red-team|rfc|risks] [--focus LENS] [--context PATH] [--pr
  N] [--diff] [--follow-up FILE] [--versus FILE_A FILE_B] [--interactive] [--stakeholders LIST]
  [--persona NAME_OR_DESC] [--output PATH]'
allowed-tools: ['Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-anvil.sh:*)']
hide-from-slash-command-tool: 'true'
---

# Anvil — Adversarial Thinking

Execute the setup script to initialize the debate:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-anvil.sh" $ARGUMENTS
```

You are now entering a structured adversarial debate. The Anvil stop hook will rotate you through
phases:

1. **Advocate** — Argue FOR the proposition (or AGAINST in devils-advocate mode)
2. **Critic** — Argue AGAINST the proposition (or FOR + find weaknesses in devils-advocate mode)
3. **Synthesizer** — Produce a balanced final analysis

Each time you try to stop, the hook will feed you the next phase's prompt with the full debate
transcript so far. Commit fully to each role — argue as if you genuinely hold that position.

CRITICAL: Do NOT try to be balanced during Advocate or Critic phases. Save balance for the
Synthesizer. The value of this tool comes from genuinely adversarial positions.
