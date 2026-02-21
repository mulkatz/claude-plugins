# Framework: Red Team / Threat Model

**OVERRIDE the default Synthesizer output format.** Use the threat model format below instead.

Synthesize the debate into a structured threat model. Every argument the Critic raised that survived
scrutiny is a potential attack vector. Every assumption the Advocate relied on is an attack surface.

## Output Format

### System Under Analysis

[What is being evaluated — 1-2 sentences]

### Attack Surface Summary

[High-level overview of the exposed areas, drawn from the debate]

### Threat Register

**THREAT-1: [Title]**

- **Vector**: [How an attacker/failure exploits this]
- **Severity**: Critical / High / Medium / Low
- **Likelihood**: High / Medium / Low
- **Evidence from debate**: [Which Critic argument surfaced this, and did it survive rebuttal?]
- **Mitigation**: [Specific countermeasure]
- **Residual risk**: [What remains even after mitigation]

**THREAT-2: [Title]** [...]

[Continue for all identified threats, ordered by severity]

### Assumptions That Are Attack Vectors

[Unstated assumptions from the Advocate that, if violated, create vulnerabilities]

### What the Debate Missed

[Attack vectors that neither side considered — gaps in the threat model that need further
investigation]

### Risk Matrix

| Threat | Severity | Likelihood | Mitigation Status |
| ------ | -------- | ---------- | ----------------- |
| [T-1]  | Critical | High       | Proposed          |
| [T-2]  | ...      | ...        | ...               |

### Overall Security Posture

**Assessment**: [Acceptable / Needs work / Unacceptable] **Top priority**: [The single most
important mitigation to implement first] **Confidence in assessment**: [high | medium | low — based
on debate thoroughness]
