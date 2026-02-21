# Anvil — Adversarial Thinking Plugin

## What this is

A Claude Code plugin that enables adversarial thinking through structured debates. Uses stop hook
orchestration to rotate through Advocate → Critic → Synthesizer phases, each with distinct role
prompts.

## Architecture

- **No TypeScript runtime** — the plugin is shell scripts + markdown prompts
- `bun` is used as package manager only (scripts, formatting)
- The prompts in `prompts/` ARE the product
- Stop hook (`hooks/stop-hook.sh`) is the orchestrator — it manages the state machine
- State lives in `.claude/anvil-state.local.md` (YAML frontmatter + markdown transcript)

## Key files

- `hooks/stop-hook.sh` — Core state machine and prompt routing
- `scripts/setup-anvil.sh` — Argument parsing, validation, state file creation
- `prompts/{advocate,critic,synthesizer}.md` — Role-specific instructions
- `prompts/modes/{analyst,philosopher,devils-advocate}.md` — Mode-specific tone
- `commands/anvil.md` — Entry point command

## Documentation

When a change affects user-facing behavior (new flags, new features, changed defaults, new
modes/frameworks/personas), update `README.md` accordingly:

- **New CLI flag**: Add to the options table and, if significant, add a section under Features
- **New mode/framework/persona preset**: Add to the relevant Features section with an example
- **Changed behavior**: Update any affected descriptions, examples, or the debate flow diagram
- **New script/file**: Update the Architecture tree if it's a top-level addition

## Conventions

- ADRs in `docs/adr/` for architectural decisions
- State file uses `.local.md` suffix (gitignored by Claude Code)
- All shell scripts use `set -euo pipefail`
- Frontmatter parsing with `sed`, transcript manipulation with `awk`
- Atomic file updates via temp file + `mv`

## Testing

Every change to `setup-anvil.sh` or `stop-hook.sh` MUST include corresponding test updates. Run
`bun run check` (shellcheck + all bats tests) before committing — it must pass.

### Running tests

- `bun run check` — shellcheck + full suite (use this before every commit)
- `bun run test` — all bats tests
- `bun run test:setup` — setup-anvil.sh tests only
- `bun run test:hook` — stop-hook.sh tests only
- `bun run lint` — shellcheck only

### Test structure

Tests mirror the source scripts:

| Source                   | Test directory       | What it covers                                                                                                                            |
| ------------------------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/setup-anvil.sh` | `tests/setup-anvil/` | Arg parsing, validation, state file creation, mode detection, personas, context injection, output formatting                              |
| `hooks/stop-hook.sh`     | `tests/stop-hook/`   | Entry conditions, state transitions, prompt construction, persona/stakeholder prompts, interactive mode, early completion, terminal state |
| Both combined            | `tests/integration/` | End-to-end debate cycles, shellcheck                                                                                                      |

### What to test when changing code

- **New CLI flag**: Add to `args-parsing.bats` (default + explicit value), `validation.bats`
  (missing value, invalid value), `state-file-creation.bats` (stored in frontmatter),
  `output-formatting.bats` (shown in banner/prompt)
- **New mode**: Add to `mode-detection.bats`, `prompt-construction.bats` (mode prompt included),
  `output-formatting.bats` (mode-specific research instructions if applicable)
- **New framework**: Add to `args-parsing.bats`, `validation.bats` (if constrained),
  `prompt-construction.bats` (framework prompt in synthesizer)
- **New persona preset**: Add to `persona-handling.bats` (description loaded),
  `persona-prompts.bats` (prompt content)
- **State machine change**: Add to `state-transitions.bats` (transition test),
  `full-debate-cycle.bats` (end-to-end scenario)
- **New focus lens preset**: Add to `output-formatting.bats` (evaluation criteria),
  `prompt-construction.bats` (focus in advocate/critic)

### Writing tests — conventions

- Load helpers: `load "../helpers/setup"` + any needed factories/assertions
- Use `run bash -c 'cd "$1" && shift && "$@"' _ "$TEST_DIR" "$SETUP_SCRIPT" "$@"` pattern for setup
  tests (runs in isolated dir)
- Use `run_stop_hook` from `transcript-factory.bash` for hook tests (handles stdin piping)
- Use `create_state_file KEY=VALUE ...` from `state-factory.bash` to set up hook test state
- Use `setup_hook_input "message"` to prepare transcript + hook input JSON
- Assert frontmatter with `assert_frontmatter "field" "value"`, hook output with
  `assert_block_decision`, `assert_reason_contains`, `assert_system_message_contains`
- Each test must be self-contained — no shared state, no test ordering dependencies
