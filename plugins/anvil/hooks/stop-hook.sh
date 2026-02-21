#!/bin/bash

# Anvil Stop Hook — Adversarial Debate Orchestrator
#
# State machine: advocate(R1) → critic(R1) → advocate(R2) → critic(R2) → ... → synthesizer → DONE
#
# Reads state from .claude/anvil-state.local.md, extracts last assistant output,
# appends it to the debate transcript, determines the next phase, constructs
# a role-specific prompt, and returns JSON to block exit and inject the prompt.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Check for required dependency
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: Anvil requires 'jq'. Install with: brew install jq" >&2
  exit 0
fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Check if anvil debate is active
ANVIL_STATE_FILE=".claude/anvil-state.local.md"

if [[ ! -f "$ANVIL_STATE_FILE" ]]; then
  exit 0
fi

# Helper: capitalize first letter (portable, works on macOS)
capitalize() {
  local str="$1"
  local first
  first=$(printf '%s' "${str:0:1}" | tr '[:lower:]' '[:upper:]')
  printf '%s' "${first}${str:1}"
}

# Parse YAML frontmatter (only lines between first and second ---)
FRONTMATTER=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$ANVIL_STATE_FILE")

# Helper: extract field from YAML frontmatter (pipefail-safe — won't crash if field is missing)
_fm() { printf '%s\n' "$FRONTMATTER" | { grep "^${1}:" || true; } | sed "s/^${1}: *//" | tr -d '\r'; }
# Helper: extract quoted field (strips surrounding double quotes, unescapes YAML escapes)
_fmq() {
  _fm "$1" | sed 's/^"\(.*\)"$/\1/' | awk '{
    gsub(/\\\\/, "\x01")
    gsub(/\\"/, "\"")
    gsub(/\\n/, "\n")
    gsub(/\\t/, "\t")
    gsub(/\\r/, "\r")
    gsub(/\x01/, "\\")
    printf "%s", $0
  }'
}

ACTIVE=$(_fm active)
QUESTION=$(_fmq question)
MODE=$(_fm mode)
POSITION=$(_fmq position)
ROUND=$(_fm round)
MAX_ROUNDS=$(_fm max_rounds)
PHASE=$(_fm phase)
RESEARCH=$(_fm research)
FRAMEWORK=$(_fm framework)
FOCUS=$(_fmq focus)
CONTEXT_SOURCE=$(_fmq context_source)
VERSUS=$(_fm versus)
INTERACTIVE=$(_fm interactive)
STAKEHOLDERS=$(_fmq stakeholders)
STAKEHOLDER_INDEX=$(_fm stakeholder_index)
PERSONAS=$(_fmq personas)
OUTPUT=$(_fmq output)

# Parse persona names into array
PERSONA_NAMES=()
if [[ -n "$PERSONAS" ]]; then
  IFS='|' read -ra PERSONA_NAMES <<< "$PERSONAS"
fi
PERSONA_COUNT=${#PERSONA_NAMES[@]}

# Validate state
if [[ "$ACTIVE" != "true" ]]; then
  rm -f "$ANVIL_STATE_FILE"
  exit 0
fi

if [[ ! "$ROUND" =~ ^[0-9]+$ ]]; then
  echo "Warning: Anvil state corrupted (invalid round: '$ROUND'). Cleaning up." >&2
  rm -f "$ANVIL_STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ROUNDS" =~ ^[0-9]+$ ]]; then
  echo "Warning: Anvil state corrupted (invalid max_rounds: '$MAX_ROUNDS'). Cleaning up." >&2
  rm -f "$ANVIL_STATE_FILE"
  exit 0
fi

# Validate phase
case "$PHASE" in
  advocate|critic|synthesizer|interactive-pause|stakeholder|persona) ;;
  *)
    echo "Warning: Anvil state corrupted (invalid phase: '$PHASE'). Cleaning up." >&2
    rm -f "$ANVIL_STATE_FILE"
    exit 0
    ;;
esac

# Get transcript path from hook input
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "Warning: Anvil transcript not found. Cleaning up." >&2
  rm -f "$ANVIL_STATE_FILE"
  exit 0
fi

# Extract last assistant message from transcript (JSONL format)
if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "Warning: No assistant messages in transcript. Cleaning up." >&2
  rm -f "$ANVIL_STATE_FILE"
  exit 0
fi

LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)

LAST_OUTPUT=$(printf '%s' "$LAST_LINE" | jq -r '
  .message.content |
  map(select(.type == "text")) |
  map(.text) |
  join("\n")
' 2>/dev/null || echo "")

if [[ -z "$LAST_OUTPUT" ]]; then
  echo "Warning: Empty assistant output. Cleaning up." >&2
  rm -f "$ANVIL_STATE_FILE"
  exit 0
fi

# Save the original phase for transcript attribution before any modification
ORIGINAL_PHASE="$PHASE"
ORIGINAL_ROUND="$ROUND"

# Check for early completion signal
if printf '%s' "$LAST_OUTPUT" | grep -q '<anvil-complete/>'; then
  # Strip the tag from output before appending
  LAST_OUTPUT=$(printf '%s' "$LAST_OUTPUT" | sed 's/<anvil-complete\/>//')
  # Force transition to synthesizer if not already there
  if [[ "$PHASE" != "synthesizer" ]]; then
    if [[ "$PHASE" == "stakeholder" ]]; then
      PHASE="stakeholder"
    elif [[ "$PHASE" == "persona" ]]; then
      PHASE="persona"
    else
      PHASE="critic"
    fi
    ROUND="$MAX_ROUNDS"
  fi
fi

# Append output to state file under the correct heading (use ORIGINAL phase/round)
# Skip transcript append for interactive-pause (meta-conversation, not debate content)
PHASE_UPPER=$(capitalize "$ORIGINAL_PHASE")

if [[ "$ORIGINAL_PHASE" == "interactive-pause" ]]; then
  : # Do not append interactive-pause output to debate transcript
elif [[ "$ORIGINAL_PHASE" == "stakeholder" ]]; then
  # For stakeholder mode, get the stakeholder name by index
  IFS=',' read -ra SH_LIST <<< "$STAKEHOLDERS"
  SH_IDX=$((ORIGINAL_ROUND - 1))
  SH_NAME=$(printf '%s' "${SH_LIST[$SH_IDX]}" | sed 's/^ *//;s/ *$//')
  printf '\n## Stakeholder %s: %s\n\n%s\n' "$ORIGINAL_ROUND" "$SH_NAME" "$LAST_OUTPUT" >> "$ANVIL_STATE_FILE"
elif [[ "$ORIGINAL_PHASE" == "persona" ]]; then
  # For persona rotation mode (3+ personas), label by persona name
  P_IDX=$((ORIGINAL_ROUND - 1))
  P_NAME="${PERSONA_NAMES[$P_IDX]}"
  printf '\n## Persona %s: %s\n\n%s\n' "$ORIGINAL_ROUND" "$P_NAME" "$LAST_OUTPUT" >> "$ANVIL_STATE_FILE"
elif [[ "$ORIGINAL_PHASE" == "advocate" ]] || [[ "$ORIGINAL_PHASE" == "critic" ]]; then
  # Check if this round heading already exists
  if ! grep -q "^## Round $ORIGINAL_ROUND" "$ANVIL_STATE_FILE"; then
    printf '\n## Round %s\n' "$ORIGINAL_ROUND" >> "$ANVIL_STATE_FILE"
  fi
  printf '\n### %s\n\n%s\n' "$PHASE_UPPER" "$LAST_OUTPUT" >> "$ANVIL_STATE_FILE"
elif [[ "$ORIGINAL_PHASE" == "synthesizer" ]]; then
  printf '\n## Synthesis\n\n%s\n' "$LAST_OUTPUT" >> "$ANVIL_STATE_FILE"
fi

# --- State Machine Transitions ---

NEXT_PHASE=""
NEXT_ROUND="$ROUND"

case "$PHASE" in
  advocate)
    NEXT_PHASE="critic"
    NEXT_ROUND="$ROUND"
    ;;
  critic)
    if [[ "$ROUND" -lt "$MAX_ROUNDS" ]]; then
      # In interactive mode, pause for user steering between rounds
      if [[ "$INTERACTIVE" == "true" ]]; then
        NEXT_PHASE="interactive-pause"
        NEXT_ROUND="$ROUND"
      else
        NEXT_PHASE="advocate"
        NEXT_ROUND=$((ROUND + 1))
      fi
    else
      NEXT_PHASE="synthesizer"
      NEXT_ROUND="$ROUND"
    fi
    ;;
  stakeholder)
    # Stakeholder mode: rotate through stakeholders, then synthesize
    if [[ "$ROUND" -lt "$MAX_ROUNDS" ]]; then
      NEXT_PHASE="stakeholder"
      NEXT_ROUND=$((ROUND + 1))
    else
      NEXT_PHASE="synthesizer"
      NEXT_ROUND="$ROUND"
    fi
    ;;
  persona)
    # Persona rotation mode (3+ personas): rotate through, then synthesize
    if [[ "$ROUND" -lt "$MAX_ROUNDS" ]]; then
      NEXT_PHASE="persona"
      NEXT_ROUND=$((ROUND + 1))
    else
      NEXT_PHASE="synthesizer"
      NEXT_ROUND="$ROUND"
    fi
    ;;
  interactive-pause)
    # Extract steering from the last output
    STEERING=""
    if printf '%s' "$LAST_OUTPUT" | grep -q '<anvil-steering>'; then
      STEERING=$(printf '%s' "$LAST_OUTPUT" | sed -n 's/.*<anvil-steering>\(.*\)<\/anvil-steering>.*/\1/p')
    fi
    # Check for skip-to-synthesis
    if [[ "$STEERING" == "synthesize" ]] || [[ "$STEERING" == "skip" ]]; then
      NEXT_PHASE="synthesizer"
      NEXT_ROUND="$ROUND"
    else
      NEXT_PHASE="advocate"
      NEXT_ROUND=$((ROUND + 1))
    fi
    ;;
  synthesizer)
    # Debate complete — build full report, write result, clean up

    # Determine output path
    RESULT_FILE="${OUTPUT:-.claude/anvil-result.local.md}"

    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    RESEARCH_LABEL="no"
    if [[ "$RESEARCH" == "true" ]]; then
      RESEARCH_LABEL="yes"
    fi

    # Extract debate record from state file body (everything from ## Round/Stakeholder/Persona up to ## Synthesis)
    DEBATE_RECORD=$(awk '/^## (Round|Stakeholder|Persona) [0-9]/{d=1} /^## Synthesis$/{exit} d{print}' "$ANVIL_STATE_FILE")

    # Build full report function
    build_full_report() {
      printf '# Anvil Analysis: %s\n\n' "$QUESTION"

      # Metadata blockquote
      local meta
      meta=$(printf '> **Mode**: %s | **Rounds**: %s | **Research**: %s | **Date**: %s' \
        "$MODE" "$ROUND" "$RESEARCH_LABEL" "$TIMESTAMP")
      if [[ -n "$FRAMEWORK" ]]; then
        meta=$(printf '%s\n> **Framework**: %s' "$meta" "$FRAMEWORK")
      fi
      if [[ -n "$FOCUS" ]]; then
        meta=$(printf '%s\n> **Focus**: %s' "$meta" "$FOCUS")
      fi
      if [[ -n "$CONTEXT_SOURCE" ]]; then
        meta=$(printf '%s\n> **Context**: %s' "$meta" "$CONTEXT_SOURCE")
      fi
      if [[ -n "$PERSONAS" ]]; then
        meta=$(printf '%s\n> **Personas**: %s' "$meta" "$(echo "$PERSONAS" | tr '|' ', ')")
      fi
      printf '%s\n' "$meta"

      printf '\n---\n\n'
      printf '## Executive Summary\n\n'
      printf '%s\n' "$LAST_OUTPUT"

      if [[ -n "$DEBATE_RECORD" ]]; then
        printf '\n---\n\n'
        printf '## Debate Record\n\n'
        printf '%s\n' "$DEBATE_RECORD"
      fi
    }

    # Ensure parent directory exists
    mkdir -p "$(dirname "$RESULT_FILE")"

    # Determine format and write
    TEMP_RESULT="${RESULT_FILE}.tmp.$$"
    if [[ "$RESULT_FILE" == *.html ]]; then
      # HTML export
      REPORT_SCRIPT="${PLUGIN_ROOT}/scripts/generate-report.mjs"
      if command -v bun >/dev/null 2>&1 && [[ -f "$REPORT_SCRIPT" ]]; then
        build_full_report | bun "$REPORT_SCRIPT" > "$TEMP_RESULT"
      else
        # Fallback: write markdown with warning
        {
          printf '<!-- WARNING: HTML conversion unavailable (bun not found). Markdown output below. -->\n\n'
          build_full_report
        } > "$TEMP_RESULT"
      fi
    else
      build_full_report > "$TEMP_RESULT"
    fi
    mv "$TEMP_RESULT" "$RESULT_FILE"

    rm -f "$ANVIL_STATE_FILE"
    echo "Anvil debate complete. Result saved to $RESULT_FILE"
    exit 0
    ;;
esac

# Update state file frontmatter (only within frontmatter block, not transcript body)
TEMP_FILE="${ANVIL_STATE_FILE}.tmp.$$"
awk -v next_phase="$NEXT_PHASE" -v next_round="$NEXT_ROUND" '
  /^---$/ { count++ }
  count <= 1 && /^phase: / { print "phase: " next_phase; next }
  count <= 1 && /^round: / { print "round: " next_round; next }
  count <= 1 && /^stakeholder_index: / { print "stakeholder_index: " next_round; next }
  { print }
' "$ANVIL_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$ANVIL_STATE_FILE"

# --- Construct Next Prompt ---

# Extract the debate transcript so far (everything after second ---)
TRANSCRIPT_SO_FAR=$(awk '/^---$/{i++; next} i>=2' "$ANVIL_STATE_FILE")

# Handle interactive-pause prompt separately (it's a meta-phase, not a debate phase)
if [[ "$NEXT_PHASE" == "interactive-pause" ]]; then
  PAUSE_PROMPT="# Round $ROUND Complete — Interactive Steering

Summarize this round of the debate concisely:
1. **Advocate's key arguments** this round (2-3 bullet points)
2. **Critic's key counterarguments** this round (2-3 bullet points)
3. **Current state**: Which side seems stronger so far?

Then ask the user how they want to steer the next round. Use the AskUserQuestion tool with these options:
- \"Continue automatically\" — let the debate proceed without steering
- \"Focus the debate\" — provide a specific angle or constraint for the next round
- \"Skip to synthesis\" — end the debate early and produce the final analysis

After receiving the user's response, output exactly one of these tags at the END of your response:
- If the user wants to continue: \`<anvil-steering>none</anvil-steering>\`
- If the user provides direction: \`<anvil-steering>THEIR DIRECTION HERE</anvil-steering>\`
- If the user wants synthesis: \`<anvil-steering>synthesize</anvil-steering>\`

## Debate so far

$TRANSCRIPT_SO_FAR"

  SYSTEM_MSG="Anvil: INTERACTIVE PAUSE — Round $ROUND complete, awaiting user steering"

  jq -n \
    --arg prompt "$PAUSE_PROMPT" \
    --arg msg "$SYSTEM_MSG" \
    '{
      "decision": "block",
      "reason": $prompt,
      "systemMessage": $msg
    }'
  exit 0
fi

# If we just came from interactive-pause with steering, inject it
STEERING_BLOCK=""
if [[ "$PHASE" == "interactive-pause" ]] && [[ -n "$STEERING" ]] && [[ "$STEERING" != "none" ]]; then
  STEERING_BLOCK="
## User Steering Directive

The user has directed the next round to focus on: **$STEERING**

Incorporate this directive into your argument. Address the user's concern directly."
fi

# Read role prompt
if [[ "$NEXT_PHASE" == "stakeholder" ]]; then
  # Get the stakeholder name for this round
  IFS=',' read -ra SH_LIST <<< "$STAKEHOLDERS"
  SH_IDX=$((NEXT_ROUND - 1))
  SH_NAME=$(printf '%s' "${SH_LIST[$SH_IDX]}" | sed 's/^ *//;s/ *$//')
  ROLE_PROMPT="You are now embodying the **$SH_NAME** perspective. Analyze the question exclusively from this stakeholder's viewpoint. This is stakeholder $NEXT_ROUND of ${#SH_LIST[@]}."
elif [[ "$NEXT_PHASE" == "persona" ]]; then
  # Persona rotation mode (3+ personas): get persona description from state file
  P_IDX=$((NEXT_ROUND - 1))
  P_NAME="${PERSONA_NAMES[$P_IDX]}"
  # Extract persona description from state file body (stored between <!-- persona:NAME --> markers)
  P_DESC=$(awk -v name="$P_NAME" '
    index($0, "<!-- persona:" name " -->") > 0 { found=1; next }
    /<!-- \/persona -->/ { if(found) exit }
    found { print }
  ' "$ANVIL_STATE_FILE")
  if [[ -z "$P_DESC" ]]; then
    P_DESC="$P_NAME"
  fi
  ROLE_PROMPT="# Persona: $P_NAME

$P_DESC

Argue this question from your perspective. This is persona $NEXT_ROUND of $PERSONA_COUNT."
elif [[ "$PERSONA_COUNT" -eq 2 ]]; then
  # 2-persona mode: personas replace advocate/critic role prompts
  if [[ "$NEXT_PHASE" == "advocate" ]]; then
    P_NAME="${PERSONA_NAMES[0]}"
    P_DESC=$(awk -v name="$P_NAME" '
      index($0, "<!-- persona:" name " -->") > 0 { found=1; next }
      /<!-- \/persona -->/ { if(found) exit }
      found { print }
    ' "$ANVIL_STATE_FILE")
    if [[ -z "$P_DESC" ]]; then P_DESC="$P_NAME"; fi
    ROLE_PROMPT="# Persona: $P_NAME

$P_DESC

You are arguing FOR the proposition from this persona's perspective."
  elif [[ "$NEXT_PHASE" == "critic" ]]; then
    P_NAME="${PERSONA_NAMES[1]}"
    P_DESC=$(awk -v name="$P_NAME" '
      index($0, "<!-- persona:" name " -->") > 0 { found=1; next }
      /<!-- \/persona -->/ { if(found) exit }
      found { print }
    ' "$ANVIL_STATE_FILE")
    if [[ -z "$P_DESC" ]]; then P_DESC="$P_NAME"; fi
    ROLE_PROMPT="# Persona: $P_NAME

$P_DESC

You are arguing AGAINST the proposition from this persona's perspective. Challenge the previous persona's arguments."
  else
    ROLE_PROMPT=$(cat "$PLUGIN_ROOT/prompts/${NEXT_PHASE}.md" 2>/dev/null || echo "")
  fi
else
  ROLE_PROMPT=$(cat "$PLUGIN_ROOT/prompts/${NEXT_PHASE}.md" 2>/dev/null || echo "")
fi

# Read mode prompt
if [[ "$NEXT_PHASE" == "synthesizer" ]] && [[ "$MODE" == "stakeholders" ]]; then
  MODE_PROMPT="You are synthesizing a **stakeholder simulation**. Do NOT embody any single stakeholder. Instead, analyze where stakeholders aligned, where they conflicted, and what no stakeholder considered."
elif [[ "$NEXT_PHASE" == "synthesizer" ]] && [[ "$PERSONA_COUNT" -gt 0 ]]; then
  MODE_PROMPT="You are synthesizing a **persona debate**. Do NOT embody any single persona. Instead, analyze where the personas' perspectives aligned, where they conflicted, and what insights emerge from combining their viewpoints."
elif [[ "$PERSONA_COUNT" -gt 0 ]]; then
  MODE_PROMPT="You are operating in **persona debate mode**. Instead of generic Advocate/Critic roles, each side is represented by a specific persona with their own worldview, priorities, and expertise. Argue authentically from your persona's perspective."
else
  MODE_PROMPT=$(cat "$PLUGIN_ROOT/prompts/modes/${MODE}.md" 2>/dev/null || echo "")
fi

# Read framework template (synthesizer only)
FRAMEWORK_PROMPT=""
if [[ "$NEXT_PHASE" == "synthesizer" ]] && [[ -n "$FRAMEWORK" ]]; then
  FRAMEWORK_PROMPT=$(cat "$PLUGIN_ROOT/prompts/frameworks/${FRAMEWORK}.md" 2>/dev/null || echo "")
fi

# Build research instructions if enabled (mode-aware)
RESEARCH_BLOCK=""
if [[ "$RESEARCH" == "true" ]]; then
  # Mode-specific research guidance
  RESEARCH_FOCUS_ADVOCATE=""
  RESEARCH_FOCUS_CRITIC=""
  RESEARCH_FOCUS_STAKEHOLDER=""
  RESEARCH_FOCUS_SYNTH=""
  case "$MODE" in
    analyst)
      RESEARCH_FOCUS_ADVOCATE="- Search for data, studies, benchmarks, and case studies that SUPPORT your position
- Look for real-world examples, success stories, and adoption metrics
- Find specific numbers, dates, and measurable outcomes — not vague generalities"
      RESEARCH_FOCUS_CRITIC="- Search for data that CONTRADICTS the Advocate's claims
- Look for failure cases, counter-examples, and cautionary tales
- Fact-check specific claims the Advocate made — verify or debunk them
- Find alternative perspectives and competing studies"
      RESEARCH_FOCUS_SYNTH="- Verify key statistics and data points cited during the debate
- Check if cited sources actually support the claims made
- If a claim lacks a source, search to confirm or refute it"
      ;;
    philosopher)
      RESEARCH_FOCUS_ADVOCATE="- Search for philosophical arguments, frameworks, and thinkers that support your position
- Look for historical precedents and analogous ethical dilemmas
- Find thought experiments or academic papers that illuminate your thesis
- Search for how this question has been debated in philosophy, ethics, or social theory"
      RESEARCH_FOCUS_CRITIC="- Search for philosophical counter-arguments and opposing frameworks
- Look for historical cases where similar reasoning led to problematic outcomes
- Find critiques of the frameworks the Advocate relied on
- Search for thinkers who have argued against this position"
      RESEARCH_FOCUS_SYNTH="- Verify if cited philosophical arguments and thinkers are accurately represented
- Check if historical precedents cited actually support the claims made
- Search for any major philosophical framework that both sides overlooked"
      ;;
    devils-advocate)
      RESEARCH_FOCUS_ADVOCATE="- Search for evidence that UNDERMINES the user's stated position
- Look for failure cases, risks, and overlooked consequences
- Find real-world examples where similar positions turned out wrong
- Search for the strongest arguments against the user's stance"
      RESEARCH_FOCUS_CRITIC="- Search for evidence that SUPPORTS and DEFENDS the user's position
- Look for success stories and data that validate the user's stance
- Fact-check the Advocate's attacks — find where they're wrong or exaggerated
- Search for rebuttals to the specific arguments the Advocate raised"
      RESEARCH_FOCUS_SYNTH="- Verify key claims from both the attacks and the defense
- Check if cited sources actually support the claims made
- If a claim lacks a source, search to confirm or refute it"
      ;;
    stakeholders)
      RESEARCH_FOCUS_STAKEHOLDER="- Search for real-world concerns, data, and examples relevant to THIS stakeholder's perspective
- Look for case studies where this stakeholder role was impacted by similar decisions
- Find industry benchmarks, regulations, or standards this stakeholder would reference
- Search for common failure modes that this stakeholder would worry about"
      RESEARCH_FOCUS_SYNTH="- Verify key claims and data points cited by the various stakeholders
- Check if cited industry standards or regulations are accurately represented
- Search for stakeholder perspectives that may have been underrepresented"
      ;;
  esac

  if [[ "$NEXT_PHASE" == "advocate" ]]; then
    RESEARCH_BLOCK="
## Research Mode ENABLED

Before constructing your argument, use **WebSearch** to research the topic. Ground your claims in real evidence:
$RESEARCH_FOCUS_ADVOCATE
- Cite your sources inline: [Source Title](URL)
- PREFER researched evidence with real URLs over claims from memory

Perform at least 2-3 targeted searches. Respond to the Critic's points from the previous round with researched counter-evidence where possible.

If WebSearch is unavailable, proceed without research and note that evidence is based on training data only."
  elif [[ "$NEXT_PHASE" == "critic" ]]; then
    RESEARCH_BLOCK="
## Research Mode ENABLED

Before constructing your critique, use **WebSearch** to research counter-evidence. Ground your critique in real evidence:
$RESEARCH_FOCUS_CRITIC
- Cite your sources inline: [Source Title](URL)
- PREFER researched evidence with real URLs over claims from memory

Perform at least 2-3 targeted searches. If the Advocate cited sources, verify their accuracy.

If WebSearch is unavailable, proceed without research and note that evidence is based on training data only."
  elif [[ "$NEXT_PHASE" == "stakeholder" ]]; then
    RESEARCH_BLOCK="
## Research Mode ENABLED

Before analyzing from this stakeholder's perspective, use **WebSearch** to research relevant evidence:
$RESEARCH_FOCUS_STAKEHOLDER
- Cite your sources inline: [Source Title](URL)
- PREFER researched evidence with real URLs over claims from memory

Perform at least 2-3 targeted searches relevant to this stakeholder's domain and concerns.

If WebSearch is unavailable, proceed without research and note that evidence is based on training data only."
  elif [[ "$NEXT_PHASE" == "persona" ]]; then
    RESEARCH_BLOCK="
## Research Mode ENABLED

Before arguing from your persona's perspective, use **WebSearch** to research relevant evidence:
- Search for real-world data, examples, and evidence that this persona would find compelling
- Look for information relevant to this persona's domain of expertise and concerns
- Find specific facts, statistics, or case studies that support your persona's argument
- Cite your sources inline: [Source Title](URL)
- PREFER researched evidence with real URLs over claims from memory

Perform at least 2-3 targeted searches relevant to your persona's perspective.

If WebSearch is unavailable, proceed without research and note that evidence is based on training data only."
  elif [[ "$NEXT_PHASE" == "synthesizer" ]]; then
    RESEARCH_BLOCK="
## Research Mode ENABLED

Before synthesizing, use **WebSearch** to VERIFY claims from both sides. You are NOT introducing new arguments — you are fact-checking the debate:
$RESEARCH_FOCUS_SYNTH
- Cite your verification sources inline: [Source Title](URL)

Perform 1-2 targeted verification searches. In your synthesis, explicitly note which evidence held up under scrutiny and which didn't. Do NOT add new perspectives — only assess what was already argued.

If WebSearch is unavailable, proceed without research and note that claims could not be independently verified."
  fi
fi

# Build the full prompt
FULL_PROMPT="$MODE_PROMPT

$ROLE_PROMPT"

if [[ -n "$FRAMEWORK_PROMPT" ]]; then
  FULL_PROMPT="$FULL_PROMPT

$FRAMEWORK_PROMPT"
fi

# Inject focus lens for advocate and critic phases
if [[ -n "$FOCUS" ]] && [[ "$NEXT_PHASE" != "synthesizer" ]]; then
  FOCUS_DESCRIPTION=""
  case "$FOCUS" in
    security)
      FOCUS_DESCRIPTION="Attack surface, vulnerabilities, compliance, data exposure, authentication/authorization, supply chain risks." ;;
    performance)
      FOCUS_DESCRIPTION="Latency, throughput, resource consumption, scalability limits, bottlenecks, caching implications." ;;
    developer-experience)
      FOCUS_DESCRIPTION="Learning curve, tooling ecosystem, debugging experience, documentation quality, onboarding time, API ergonomics." ;;
    operational-cost)
      FOCUS_DESCRIPTION="Infrastructure costs, maintenance burden, licensing, required team size, hidden operational overhead." ;;
    maintainability)
      FOCUS_DESCRIPTION="Code complexity, coupling, testability, upgrade path, technical debt trajectory, bus factor." ;;
    *)
      FOCUS_DESCRIPTION="" ;;
  esac

  FULL_PROMPT="$FULL_PROMPT

## Focus Lens: $FOCUS

CONSTRAIN your argument to this evaluation dimension. Do not address other dimensions unless they directly intersect with this focus."

  if [[ -n "$FOCUS_DESCRIPTION" ]]; then
    FULL_PROMPT="$FULL_PROMPT
Evaluate through: $FOCUS_DESCRIPTION"
  else
    FULL_PROMPT="$FULL_PROMPT
Evaluate exclusively through the lens of: **$FOCUS**"
  fi
fi

# Inject steering directive from interactive mode
if [[ -n "$STEERING_BLOCK" ]]; then
  FULL_PROMPT="$FULL_PROMPT
$STEERING_BLOCK"
fi

# Inject versus framing for advocate and critic
if [[ "$VERSUS" == "true" ]] && [[ "$NEXT_PHASE" != "synthesizer" ]]; then
  if [[ "$NEXT_PHASE" == "advocate" ]]; then
    FULL_PROMPT="$FULL_PROMPT

## VERSUS MODE

You are defending **Position A**. Argue why Position A's analysis and conclusions are stronger than Position B's. Reference specific arguments from both positions."
  elif [[ "$NEXT_PHASE" == "critic" ]]; then
    FULL_PROMPT="$FULL_PROMPT

## VERSUS MODE

You are defending **Position B**. Argue why Position B's analysis and conclusions are stronger than Position A's. Reference specific arguments from both positions."
  fi
fi

FULL_PROMPT="$FULL_PROMPT
$RESEARCH_BLOCK

---

**Question under debate:** $QUESTION"

if [[ "$POSITION" != "null" ]] && [[ -n "$POSITION" ]]; then
  FULL_PROMPT="$FULL_PROMPT

**User's stated position:** $POSITION"
fi

FULL_PROMPT="$FULL_PROMPT

## Debate so far

$TRANSCRIPT_SO_FAR

---

You are now in the **$(capitalize "$NEXT_PHASE")** phase"

if [[ "$NEXT_PHASE" == "stakeholder" ]]; then
  FULL_PROMPT="$FULL_PROMPT — **$SH_NAME** perspective ($NEXT_ROUND of $MAX_ROUNDS)"
elif [[ "$NEXT_PHASE" != "synthesizer" ]]; then
  FULL_PROMPT="$FULL_PROMPT (Round $NEXT_ROUND of $MAX_ROUNDS)"
fi

FULL_PROMPT="$FULL_PROMPT. Read the debate above carefully, then produce your response."

# Build system message
if [[ "$NEXT_PHASE" == "synthesizer" ]]; then
  SYSTEM_MSG="Anvil: SYNTHESIZER phase — produce balanced final analysis"
elif [[ "$NEXT_PHASE" == "stakeholder" ]]; then
  SYSTEM_MSG="Anvil: STAKEHOLDER phase — $SH_NAME perspective ($NEXT_ROUND of $MAX_ROUNDS)"
elif [[ "$NEXT_PHASE" == "persona" ]]; then
  SYSTEM_MSG="Anvil: PERSONA phase — ${PERSONA_NAMES[$((NEXT_ROUND - 1))]} ($NEXT_ROUND of $MAX_ROUNDS)"
elif [[ "$PERSONA_COUNT" -eq 2 ]]; then
  if [[ "$NEXT_PHASE" == "advocate" ]]; then
    SYSTEM_MSG="Anvil: ${PERSONA_NAMES[0]} (ADVOCATE) — Round $NEXT_ROUND of $MAX_ROUNDS"
  else
    SYSTEM_MSG="Anvil: ${PERSONA_NAMES[1]} (CRITIC) — Round $NEXT_ROUND of $MAX_ROUNDS"
  fi
else
  SYSTEM_MSG="Anvil: $(printf '%s' "$NEXT_PHASE" | tr '[:lower:]' '[:upper:]') phase — Round $NEXT_ROUND of $MAX_ROUNDS"
fi

# Output JSON to block exit and inject next prompt
jq -n \
  --arg prompt "$FULL_PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
