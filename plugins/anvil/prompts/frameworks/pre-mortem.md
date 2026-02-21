# Framework: Pre-Mortem Analysis

**OVERRIDE the default Synthesizer output format.** Use the pre-mortem format below instead.

Imagine it is 6 months from now. The decision was made. It failed. Your job is to reverse-engineer
why, using the debate as your evidence base.

## Output Format

### The Decision

[What was decided, in 1 sentence]

### The Failure Scenario

[Paint a vivid, specific picture of what failure looks like. Not vague doom — concrete, plausible
failure.]

### Root Causes of Failure

**Cause 1: [Title]** (Likelihood: high/medium/low) [How this cause leads to failure. Draw from
Critic's arguments that survived scrutiny.]

> _Early warning sign_: [What you'd observe 1-2 months in if this is happening] _Mitigation_: [What
> > could prevent or reduce this risk]

**Cause 2: [Title]** (Likelihood: high/medium/low) [...]

[Continue for 3-5 causes, ordered by likelihood]

### What Nobody Considered

[Failure modes that NEITHER the Advocate nor Critic raised — blind spots revealed by the pre-mortem
framing]

### The Overlooked Dependencies

[External factors, assumptions, or dependencies that could independently cause failure regardless of
the decision's merits]

### Survivability Assessment

**Will this decision survive 6 months?** [Yes / Probably / Uncertain / Probably not] **Biggest
single risk**: [The one thing most likely to kill it] **Strongest safeguard**: [The one thing most
likely to save it]

### Recommended Safeguards

[Concrete actions to take NOW to reduce the probability of each failure mode — ordered by impact]
