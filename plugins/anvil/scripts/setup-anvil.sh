#!/bin/bash

# Anvil Setup — Parse arguments, create state file, output initial prompt
# Called by the /anvil command via commands/anvil.md

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Defaults
MODE="analyst"
ROUNDS=3
POSITION=""
RESEARCH=false
FRAMEWORK=""
FOCUS=""
CONTEXT_PATHS=()
CONTEXT_PR=""
CONTEXT_DIFF=false
FOLLOW_UP=""
VERSUS_A=""
VERSUS_B=""
INTERACTIVE=false
STAKEHOLDERS=""
OUTPUT=""
PERSONAS=()
MODE_EXPLICIT=false
QUESTION_PARTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --mode)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --mode requires a value (analyst, philosopher, devils-advocate)" >&2
        exit 1
      fi
      MODE="$2"
      MODE_EXPLICIT=true
      shift 2
      ;;
    --rounds)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --rounds requires a number" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --rounds must be a positive integer (got: '$2')" >&2
        exit 1
      fi
      ROUNDS="$2"
      shift 2
      ;;
    --position)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --position requires a value" >&2
        exit 1
      fi
      POSITION="$2"
      shift 2
      ;;
    --research)
      RESEARCH=true
      shift
      ;;
    --framework)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --framework requires a value (adr, pre-mortem, red-team, rfc, risks)" >&2
        exit 1
      fi
      FRAMEWORK="$2"
      shift 2
      ;;
    --focus)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --focus requires a value (security, performance, developer-experience, operational-cost, maintainability, or custom)" >&2
        exit 1
      fi
      FOCUS="$2"
      shift 2
      ;;
    --context)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --context requires a path (file or directory)" >&2
        exit 1
      fi
      CONTEXT_PATHS+=("$2")
      shift 2
      ;;
    --pr)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --pr requires a PR number" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --pr must be a number (got: '$2')" >&2
        exit 1
      fi
      CONTEXT_PR="$2"
      shift 2
      ;;
    --diff)
      CONTEXT_DIFF=true
      shift
      ;;
    --follow-up)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --follow-up requires a file path" >&2
        exit 1
      fi
      FOLLOW_UP="$2"
      shift 2
      ;;
    --interactive)
      INTERACTIVE=true
      shift
      ;;
    --stakeholders)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --stakeholders requires a comma-separated list (e.g., engineering,product,business)" >&2
        exit 1
      fi
      STAKEHOLDERS="$2"
      shift 2
      ;;
    --versus)
      if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
        echo "Error: --versus requires two file paths" >&2
        echo "Usage: /anvil --versus result-a.md result-b.md" >&2
        exit 1
      fi
      VERSUS_A="$2"
      VERSUS_B="$3"
      shift 3
      ;;
    --persona)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --persona requires a value (preset name or free-text description)" >&2
        echo "Presets: security-engineer, startup-cfo, junior-developer, end-user" >&2
        exit 1
      fi
      PERSONAS+=("$2")
      shift 2
      ;;
    --output)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --output requires a file path" >&2
        exit 1
      fi
      OUTPUT="$2"
      shift 2
      ;;
    *)
      QUESTION_PARTS+=("$1")
      shift
      ;;
  esac
done

QUESTION="${QUESTION_PARTS[*]:-}"

# Validate --follow-up file
if [[ -n "$FOLLOW_UP" ]]; then
  if [[ ! -f "$FOLLOW_UP" ]]; then
    echo "Error: Follow-up file not found: $FOLLOW_UP" >&2
    exit 1
  fi
fi

# Validate --versus files
if [[ -n "$VERSUS_A" ]]; then
  if [[ ! -f "$VERSUS_A" ]]; then
    echo "Error: Versus file not found: $VERSUS_A" >&2
    exit 1
  fi
  if [[ ! -f "$VERSUS_B" ]]; then
    echo "Error: Versus file not found: $VERSUS_B" >&2
    exit 1
  fi
fi

# Validate question (--versus auto-generates a question)
if [[ -n "$VERSUS_A" ]] && [[ -z "$QUESTION" ]]; then
  QUESTION="Which analysis is stronger and why?"
fi

if [[ -z "$QUESTION" ]]; then
  echo "Error: No question provided." >&2
  echo "" >&2
  echo "Usage: /anvil \"Should we use microservices?\" [--mode analyst] [--rounds 3]" >&2
  exit 1
fi

# Auto-set stakeholders mode if --stakeholders provided without --mode
if [[ -n "$STAKEHOLDERS" ]] && [[ "$MODE" == "analyst" ]]; then
  MODE="stakeholders"
fi

# Validate mode
case "$MODE" in
  analyst|philosopher|devils-advocate|stakeholders) ;;
  *)
    echo "Error: Invalid mode '$MODE'. Must be one of: analyst, philosopher, devils-advocate, stakeholders" >&2
    exit 1
    ;;
esac

# Set default stakeholders if mode is stakeholders but no custom list
if [[ "$MODE" == "stakeholders" ]] && [[ -z "$STAKEHOLDERS" ]]; then
  STAKEHOLDERS="Engineering Team,Product/UX,Business/Management"
fi

# Validate --stakeholders requires stakeholders mode
if [[ -n "$STAKEHOLDERS" ]] && [[ "$MODE" != "stakeholders" ]]; then
  echo "Error: --stakeholders can only be used with --mode stakeholders" >&2
  exit 1
fi

# Validate --persona is mutually exclusive with --mode (unless mode was auto-set to analyst)
PERSONA_COUNT=${#PERSONAS[@]}
if [[ "$PERSONA_COUNT" -gt 0 ]]; then
  # Check mutual exclusion: --persona conflicts with explicit --mode
  if [[ "$MODE_EXPLICIT" == "true" ]]; then
    echo "Error: --persona and --mode are mutually exclusive. Personas replace the debate mode entirely." >&2
    exit 1
  fi
  # Need at least 2 personas for a debate
  if [[ "$PERSONA_COUNT" -lt 2 ]]; then
    echo "Error: --persona requires at least 2 personas for a debate." >&2
    echo "Usage: /anvil \"topic\" --persona \"persona A\" --persona \"persona B\"" >&2
    exit 1
  fi
  # Validate persona names before processing
  for pname in "${PERSONAS[@]}"; do
    if [[ "$pname" == *"|"* ]]; then
      echo "Error: persona name cannot contain '|' (reserved separator): $pname" >&2
      exit 1
    fi
    if [[ "$pname" == *"<!--"* ]] || [[ "$pname" == *"-->"* ]]; then
      echo "Error: persona name cannot contain HTML comment markers: $pname" >&2
      exit 1
    fi
    if [[ "$pname" == *$'\n'* ]] || [[ "$pname" == *$'\r'* ]]; then
      echo "Error: persona name cannot contain newline or carriage return characters" >&2
      exit 1
    fi
  done
  # Resolve preset vs custom persona descriptions
  PERSONA_DESCRIPTIONS=()
  PERSONA_NAMES=()
  for persona in "${PERSONAS[@]}"; do
    preset_file="$PLUGIN_ROOT/prompts/personas/${persona}.md"
    if [[ -f "$preset_file" ]]; then
      PERSONA_DESCRIPTIONS+=("$(cat "$preset_file")")
      PERSONA_NAMES+=("$persona")
    else
      # Free-text persona — use description directly
      PERSONA_DESCRIPTIONS+=("$persona")
      PERSONA_NAMES+=("$persona")
    fi
  done
  # --interactive not supported with 3+ personas (rotation has no critic phase)
  if [[ "$INTERACTIVE" == "true" ]] && [[ "$PERSONA_COUNT" -gt 2 ]]; then
    echo "Error: --interactive is not supported with 3+ personas. Interactive steering requires the advocate/critic cycle." >&2
    exit 1
  fi
fi

# Validate framework
if [[ -n "$FRAMEWORK" ]]; then
  case "$FRAMEWORK" in
    adr|pre-mortem|red-team|rfc|risks) ;;
    *)
      echo "Error: Invalid framework '$FRAMEWORK'. Must be one of: adr, pre-mortem, red-team, rfc, risks" >&2
      exit 1
      ;;
  esac
fi

# Validate rounds (skip for stakeholders/personas — rounds auto-calculated)
if [[ "$MODE" == "stakeholders" ]]; then
  # Count stakeholders (comma-separated)
  IFS=',' read -ra STAKEHOLDER_LIST <<< "$STAKEHOLDERS"
  ROUNDS=${#STAKEHOLDER_LIST[@]}
elif [[ "$PERSONA_COUNT" -gt 2 ]]; then
  # 3+ personas: each gets one round (rotation), then synthesizer
  ROUNDS=$PERSONA_COUNT
elif [[ "$ROUNDS" -lt 1 ]] || [[ "$ROUNDS" -gt 5 ]]; then
  echo "Error: --rounds must be between 1 and 5 (got: $ROUNDS)" >&2
  exit 1
fi

# Validate position for devils-advocate mode
if [[ "$MODE" == "devils-advocate" ]] && [[ -z "$POSITION" ]]; then
  echo "Error: --position is required for devils-advocate mode" >&2
  echo "" >&2
  echo "Usage: /anvil \"topic\" --mode devils-advocate --position \"I believe X because Y\"" >&2
  exit 1
fi

# --- Context Generation ---

CONTEXT_MAX_CHARS=5000
CONTEXT_BODY=""
CONTEXT_SOURCE=""

# Generate context summary for a directory
generate_dir_context() {
  local dir_path="$1"
  local output=""

  # File tree (max depth 3, truncated)
  output+="### Directory: $dir_path"$'\n\n'
  output+='```'$'\n'
  if command -v tree >/dev/null 2>&1; then
    output+="$(tree -L 3 --noreport "$dir_path" 2>/dev/null | head -50)"
  else
    output+="$(find "$dir_path" -maxdepth 3 -type f 2>/dev/null | sort | head -50)"
  fi
  output+=$'\n''```'$'\n\n'

  # Key declarations (language-agnostic heuristic)
  output+="**Key declarations:**"$'\n''```'$'\n'
  output+="$(grep -rn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
    --include='*.py' --include='*.go' --include='*.rs' --include='*.java' --include='*.rb' \
    --include='*.swift' --include='*.kt' --include='*.cs' --include='*.sh' \
    -E '^\s*(export\s+)?(class |interface |type |enum |function |def |fn |func |pub |struct |trait |const |let |var |async function )' \
    "$dir_path" 2>/dev/null | head -40 || echo "(no declarations found)")"
  output+=$'\n''```'$'\n'

  printf '%s' "$output"
}

# Generate context summary for a file
generate_file_context() {
  local file_path="$1"
  local output=""
  local line_count
  line_count=$(wc -l < "$file_path" 2>/dev/null | tr -d ' ' || echo "0")

  output+="### File: $file_path ($line_count lines)"$'\n\n'
  output+='```'$'\n'
  if [[ "$line_count" -gt 150 ]]; then
    output+="$(head -150 "$file_path")"
    output+=$'\n'"... (truncated, $line_count total lines)"
  else
    output+="$(cat "$file_path")"
  fi
  output+=$'\n''```'$'\n'

  printf '%s' "$output"
}

# Generate context from PR diff
generate_pr_context() {
  local pr_num="$1"
  local output=""

  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: --pr requires the GitHub CLI (gh). Install with: brew install gh" >&2
    exit 1
  fi

  output+="### PR #$pr_num"$'\n\n'

  # Get PR title and body
  local pr_info
  pr_info=$(gh pr view "$pr_num" --json title,body --jq '"**" + .title + "**\n\n" + .body' 2>/dev/null || echo "(could not fetch PR info)")
  output+="$pr_info"$'\n\n'

  output+='```diff'$'\n'
  output+="$(gh pr diff "$pr_num" 2>/dev/null | head -300 || echo "(could not fetch PR diff)")"
  output+=$'\n''```'$'\n'

  printf '%s' "$output"
}

# Generate context from uncommitted changes
generate_diff_context() {
  local output=""

  output+="### Uncommitted Changes"$'\n\n'
  output+='```diff'$'\n'

  local staged
  staged=$(git diff --cached 2>/dev/null || echo "")
  local unstaged
  unstaged=$(git diff 2>/dev/null || echo "")

  if [[ -n "$staged" ]]; then
    output+="# Staged changes:"$'\n'
    output+="$(printf '%s' "$staged" | head -200)"$'\n'
  fi
  if [[ -n "$unstaged" ]]; then
    output+="# Unstaged changes:"$'\n'
    output+="$(printf '%s' "$unstaged" | head -200)"$'\n'
  fi
  if [[ -z "$staged" ]] && [[ -z "$unstaged" ]]; then
    output+="(no uncommitted changes)"$'\n'
  fi

  output+=$'\n''```'$'\n'

  printf '%s' "$output"
}

# Build context if any context source specified
HAS_CONTEXT=false
if [[ ${#CONTEXT_PATHS[@]} -gt 0 ]] || [[ -n "$CONTEXT_PR" ]] || [[ "$CONTEXT_DIFF" == "true" ]]; then
  HAS_CONTEXT=true
  CONTEXT_BODY="## Codebase Context"$'\n'

  # Process --context paths
  for ctx_path in "${CONTEXT_PATHS[@]+"${CONTEXT_PATHS[@]}"}"; do
    if [[ ! -e "$ctx_path" ]]; then
      echo "Error: Context path not found: $ctx_path" >&2
      exit 1
    fi
    if [[ -d "$ctx_path" ]]; then
      CONTEXT_BODY+=$'\n'"$(generate_dir_context "$ctx_path")"$'\n'
      CONTEXT_SOURCE+="${ctx_path} "
    elif [[ -f "$ctx_path" ]]; then
      CONTEXT_BODY+=$'\n'"$(generate_file_context "$ctx_path")"$'\n'
      CONTEXT_SOURCE+="${ctx_path} "
    fi
  done

  # Process --pr
  if [[ -n "$CONTEXT_PR" ]]; then
    CONTEXT_BODY+=$'\n'"$(generate_pr_context "$CONTEXT_PR")"$'\n'
    CONTEXT_SOURCE+="PR #${CONTEXT_PR} "
  fi

  # Process --diff
  if [[ "$CONTEXT_DIFF" == "true" ]]; then
    CONTEXT_BODY+=$'\n'"$(generate_diff_context)"$'\n'
    CONTEXT_SOURCE+="uncommitted diff "
  fi

  # Truncate context if too long
  CONTEXT_LEN=${#CONTEXT_BODY}
  if [[ "$CONTEXT_LEN" -gt "$CONTEXT_MAX_CHARS" ]]; then
    CONTEXT_BODY="${CONTEXT_BODY:0:$CONTEXT_MAX_CHARS}"$'\n\n'"*... (context truncated at $CONTEXT_MAX_CHARS chars)*"
  fi

  CONTEXT_SOURCE=$(printf '%s' "$CONTEXT_SOURCE" | sed 's/ $//')
fi

# Check for existing active debate
ANVIL_STATE_FILE=".claude/anvil-state.local.md"
if [[ -f "$ANVIL_STATE_FILE" ]]; then
  echo "Error: An Anvil debate is already active." >&2
  echo "Use /anvil-cancel to cancel it, or /anvil-status to check progress." >&2
  exit 1
fi

# Create .claude directory if needed
mkdir -p .claude

# Escape strings for YAML double-quoted values
yaml_escape() {
  local s="$1"
  s="${s//\\/\\\\}"    # \ → \\  (must be first)
  s="${s//\"/\\\"}"    # " → \"
  s="${s//$'\n'/\\n}"  # newline → \n
  s="${s//$'\t'/\\t}"  # tab → \t
  s="${s//$'\r'/\\r}"  # CR → \r
  printf '%s' "$s"
}

# Format position for YAML (null if empty)
if [[ -n "$POSITION" ]]; then
  POSITION_YAML="\"$(yaml_escape "$POSITION")\""
else
  POSITION_YAML="null"
fi

# Escape question for YAML
QUESTION_YAML="\"$(yaml_escape "$QUESTION")\""

# Build personas YAML value (pipe-separated for easy parsing)
PERSONAS_YAML=""
if [[ "$PERSONA_COUNT" -gt 0 ]]; then
  PERSONAS_YAML=$(IFS='|'; echo "${PERSONA_NAMES[*]}")
fi

# Determine initial phase
if [[ "$MODE" == "stakeholders" ]]; then
  INITIAL_PHASE="stakeholder"
elif [[ "$PERSONA_COUNT" -gt 2 ]]; then
  INITIAL_PHASE="persona"
else
  INITIAL_PHASE="advocate"
fi

# Generate default output path if not specified
if [[ -z "$OUTPUT" ]]; then
  slug=$(printf '%s' "$QUESTION" | LC_ALL=C tr -dc 'A-Za-z0-9 ' | head -c 50 | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/^-//; s/-$//')
  slug="${slug:-debate}"
  OUTPUT="$HOME/Desktop/anvil-$(date +%Y-%m-%d)-${slug}.html"
fi

# Create state file
cat > "$ANVIL_STATE_FILE" <<EOF
---
active: true
question: $QUESTION_YAML
mode: $MODE
position: $POSITION_YAML
round: 1
max_rounds: $ROUNDS
phase: $INITIAL_PHASE
research: $RESEARCH
framework: $FRAMEWORK
focus: "$(yaml_escape "$FOCUS")"
context_source: "$(yaml_escape "$CONTEXT_SOURCE")"
follow_up: "$(yaml_escape "$FOLLOW_UP")"
versus: $( [[ -n "$VERSUS_A" ]] && echo "true" || echo "false" )
interactive: $INTERACTIVE
stakeholders: "$(yaml_escape "$STAKEHOLDERS")"
stakeholder_index: 1
personas: "$(yaml_escape "$PERSONAS_YAML")"
output: "$(yaml_escape "$OUTPUT")"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---
EOF

# Append persona descriptions to state file body (before any rounds)
if [[ "$PERSONA_COUNT" -gt 0 ]]; then
  for i in $(seq 0 $((PERSONA_COUNT - 1))); do
    printf '\n<!-- persona:%s -->\n%s\n<!-- /persona -->\n' "${PERSONA_NAMES[$i]}" "${PERSONA_DESCRIPTIONS[$i]}" >> "$ANVIL_STATE_FILE"
  done
fi

# Append context to state file body (before any rounds)
if [[ "$HAS_CONTEXT" == "true" ]]; then
  printf '\n%s\n' "$CONTEXT_BODY" >> "$ANVIL_STATE_FILE"
fi

# Append follow-up context
if [[ -n "$FOLLOW_UP" ]]; then
  FOLLOW_UP_CONTENT=$(cat "$FOLLOW_UP")
  printf '\n## Prior Analysis\n\nThe following is the result of a previous Anvil debate. This new debate builds on its conclusions.\n\n%s\n' "$FOLLOW_UP_CONTENT" >> "$ANVIL_STATE_FILE"
fi

# Append versus positions
if [[ -n "$VERSUS_A" ]]; then
  VERSUS_A_CONTENT=$(cat "$VERSUS_A")
  VERSUS_B_CONTENT=$(cat "$VERSUS_B")
  printf '\n## Position A\n\nSource: %s\n\n%s\n' "$VERSUS_A" "$VERSUS_A_CONTENT" >> "$ANVIL_STATE_FILE"
  printf '\n## Position B\n\nSource: %s\n\n%s\n' "$VERSUS_B" "$VERSUS_B_CONTENT" >> "$ANVIL_STATE_FILE"
fi

# Read the initial role prompt
if [[ "$MODE" == "stakeholders" ]]; then
  # For stakeholders mode, get the first stakeholder role
  IFS=',' read -ra STAKEHOLDER_LIST <<< "$STAKEHOLDERS"
  FIRST_STAKEHOLDER=$(printf '%s' "${STAKEHOLDER_LIST[0]}" | sed 's/^ *//;s/ *$//')
  ROLE_PROMPT_INITIAL="You are now embodying the **$FIRST_STAKEHOLDER** perspective. Analyze the question exclusively from this stakeholder's viewpoint."
elif [[ "$PERSONA_COUNT" -gt 2 ]]; then
  # 3+ personas: rotation mode, first persona gets Round 1
  ROLE_PROMPT_INITIAL="# Persona: ${PERSONA_NAMES[0]}

${PERSONA_DESCRIPTIONS[0]}

Argue this question from your perspective. This is persona 1 of $PERSONA_COUNT."
elif [[ "$PERSONA_COUNT" -eq 2 ]]; then
  # 2 personas: first persona is the Advocate
  ROLE_PROMPT_INITIAL="# Persona: ${PERSONA_NAMES[0]}

${PERSONA_DESCRIPTIONS[0]}

You are arguing FOR the proposition from this persona's perspective."
else
  ROLE_PROMPT_INITIAL=$(cat "$PLUGIN_ROOT/prompts/advocate.md")
fi

# Read mode prompt (personas don't use mode prompts — the persona IS the mode)
if [[ "$PERSONA_COUNT" -gt 0 ]]; then
  MODE_PROMPT="You are operating in **persona debate mode**. Instead of generic Advocate/Critic roles, each side is represented by a specific persona with their own worldview, priorities, and expertise. Argue authentically from your persona's perspective."
else
  MODE_PROMPT=$(cat "$PLUGIN_ROOT/prompts/modes/${MODE}.md")
fi

# Build the initial prompt
echo ""
echo "============================================================"
echo "  ANVIL — Adversarial Thinking"
echo "============================================================"
echo ""
echo "  Question:  $QUESTION"
echo "  Mode:      $MODE"
echo "  Rounds:    $ROUNDS"
if [[ -n "$POSITION" ]]; then
  echo "  Position:  $POSITION"
fi
if [[ -n "$FRAMEWORK" ]]; then
  echo "  Framework: $FRAMEWORK"
fi
if [[ -n "$FOCUS" ]]; then
  echo "  Focus:     $FOCUS"
fi
if [[ "$HAS_CONTEXT" == "true" ]]; then
  echo "  Context:   $CONTEXT_SOURCE"
fi
if [[ -n "$FOLLOW_UP" ]]; then
  echo "  Follow-up: $FOLLOW_UP"
fi
echo "  Output:    $OUTPUT"
if [[ -n "$VERSUS_A" ]]; then
  echo "  Versus:    $VERSUS_A vs $VERSUS_B"
fi
if [[ "$INTERACTIVE" == "true" ]]; then
  echo "  Interactive: ENABLED (you can steer between rounds)"
fi
if [[ "$RESEARCH" == "true" ]]; then
  echo "  Research:  ENABLED (WebSearch + WebFetch)"
fi
echo ""
if [[ "$MODE" == "stakeholders" ]]; then
  echo "  Stakeholders: $STAKEHOLDERS"
  echo "  Phase:     STAKEHOLDER 1 — $FIRST_STAKEHOLDER"
  echo ""
  echo "  The simulation will cycle through:"
  echo "    Stakeholder 1 → Stakeholder 2 → ... → Synthesizer"
elif [[ "$PERSONA_COUNT" -gt 2 ]]; then
  echo "  Personas:  ${PERSONA_NAMES[*]}"
  echo "  Phase:     PERSONA 1 — ${PERSONA_NAMES[0]}"
  echo ""
  echo "  The debate will cycle through:"
  echo "    Persona 1 → Persona 2 → ... → Synthesizer"
elif [[ "$PERSONA_COUNT" -eq 2 ]]; then
  echo "  Personas:  ${PERSONA_NAMES[0]} vs ${PERSONA_NAMES[1]}"
  echo "  Phase:     ADVOCATE (${PERSONA_NAMES[0]}) — Round 1 of $ROUNDS"
  echo ""
  echo "  The debate will cycle through:"
  echo "    ${PERSONA_NAMES[0]} (Advocate) → ${PERSONA_NAMES[1]} (Critic) → ... → Synthesizer"
else
  echo "  Phase:     ADVOCATE (Round 1 of $ROUNDS)"
  echo ""
  echo "  The debate will cycle through:"
  echo "    Advocate → Critic → ... → Synthesizer"
fi
echo ""
echo "  When you finish each phase, the stop hook will"
echo "  automatically feed you the next role."
echo ""
echo "============================================================"
echo ""
echo "$MODE_PROMPT"
echo ""
echo "$ROLE_PROMPT_INITIAL"
echo ""
echo "---"
echo ""
echo "**Question under debate:** $QUESTION"
if [[ -n "$POSITION" ]]; then
  echo ""
  echo "**User's stated position:** $POSITION"
fi
if [[ "$HAS_CONTEXT" == "true" ]]; then
  echo ""
  printf '%s\n' "$CONTEXT_BODY"
fi
if [[ -n "$FOLLOW_UP" ]]; then
  echo ""
  echo "## Prior Analysis"
  echo ""
  echo "The following is the result of a previous Anvil debate. This new debate builds on its conclusions."
  echo ""
  printf '%s\n' "$FOLLOW_UP_CONTENT"
fi
if [[ -n "$VERSUS_A" ]]; then
  echo ""
  echo "## Position A (Source: $VERSUS_A)"
  echo ""
  printf '%s\n' "$VERSUS_A_CONTENT"
  echo ""
  echo "## Position B (Source: $VERSUS_B)"
  echo ""
  printf '%s\n' "$VERSUS_B_CONTENT"
  echo ""
  echo "**VERSUS MODE:** As the Advocate, defend Position A. Argue why Position A's analysis and conclusions are stronger. Reference specific arguments from both positions."
fi
if [[ -n "$FOCUS" ]]; then
  echo ""
  echo "## Focus Lens: $FOCUS"
  echo ""
  echo "CONSTRAIN your argument to this evaluation dimension. Do not address other dimensions unless they directly intersect with this focus."
  echo ""
  case "$FOCUS" in
    security)
      echo "Evaluate through: Attack surface, vulnerabilities, compliance, data exposure, authentication/authorization, supply chain risks." ;;
    performance)
      echo "Evaluate through: Latency, throughput, resource consumption, scalability limits, bottlenecks, caching implications." ;;
    developer-experience)
      echo "Evaluate through: Learning curve, tooling ecosystem, debugging experience, documentation quality, onboarding time, API ergonomics." ;;
    operational-cost)
      echo "Evaluate through: Infrastructure costs, maintenance burden, licensing, required team size, hidden operational overhead." ;;
    maintainability)
      echo "Evaluate through: Code complexity, coupling, testability, upgrade path, technical debt trajectory, bus factor." ;;
    *)
      echo "Evaluate exclusively through the lens of: **$FOCUS**" ;;
  esac
fi
if [[ "$RESEARCH" == "true" ]]; then
  echo ""
  echo "## Research Mode ENABLED"
  echo ""
  echo "Before constructing your argument, use **WebSearch** to research the topic. Ground your claims in real evidence:"
  case "$MODE" in
    analyst)
      echo "- Search for relevant data, studies, benchmarks, and case studies"
      echo "- Look for real-world examples that support your position"
      echo "- Find specific numbers, dates, and measurable outcomes — not vague generalities"
      ;;
    philosopher)
      echo "- Search for philosophical arguments, frameworks, and thinkers that support your position"
      echo "- Look for historical precedents and analogous ethical dilemmas"
      echo "- Find thought experiments or academic papers that illuminate your thesis"
      ;;
    devils-advocate)
      echo "- Search for evidence that UNDERMINES the user's stated position"
      echo "- Look for failure cases, risks, and overlooked consequences"
      echo "- Find real-world examples where similar positions turned out wrong"
      ;;
    stakeholders)
      echo "- Search for real-world concerns, data, and examples relevant to THIS stakeholder's perspective"
      echo "- Look for case studies where this stakeholder role was impacted by similar decisions"
      echo "- Find industry benchmarks, regulations, or standards this stakeholder would reference"
      echo "- Search for common failure modes that this stakeholder would worry about"
      ;;
  esac
  echo "- Cite your sources inline: [Source Title](URL)"
  echo "- PREFER researched evidence with real URLs over claims from memory"
  echo ""
  echo "Perform at least 2-3 targeted searches before writing your argument. Quality of evidence matters more than quantity."
  echo ""
  echo "If WebSearch is unavailable in this session, proceed without research and note that evidence is based on training data only."
fi
echo ""
echo "This is Round 1. No prior debate context yet. Begin your argument."
