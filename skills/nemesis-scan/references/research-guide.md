# Domain Pattern Research Guide

Reference for `nemesis-strategy` and `nemesis-researcher` agents. Defines the output format, pattern categories, and quality rules for dynamic domain discovery.

## Purpose

Replace hardcoded domain-specific references (e.g., defi-patterns.md) with patterns discovered from the actual codebase. The output must provide the same value as a hand-written domain reference: worked examples, adversarial sequences, and coupled state patterns grounded in the project's specific architecture.

## Output Format

The compiled `domain-patterns.md` must follow this structure:

```markdown
# Domain-Specific Audit Patterns

_Git hash: [short hash]_
_Target scope: [scope]_
_User hints: [hints or "none"]_
_Generated: [ISO date]_

## Domain Summary

[1-2 paragraphs: what domain this project operates in, what its core value flows are,
and what classes of bugs are most likely given the domain.]

## Worked Example — [Pattern Name]

[A concrete, multi-step walkthrough of a domain-specific bug pattern,
modeled on the style of the "Path-Dependent Accumulator Bug" example.
Must reference actual functions/types from the codebase.]

1. **TX/OP 1:** [Actor] does [action] — [state change]
2. **TX/OP 2:** [Actor] does [action] — [what goes wrong and why]
3. **TX/OP 3:** [Actor/Victim] does [action] — [reads stale/incorrect state]

**Root cause:** [The specific coupling or invariant violation]
**Generalization:** [The pattern class this belongs to]
**Verification check:** [How to test if a codebase has this bug]

[Repeat for each worked example — aim for 2-5 total]

## Domain-Specific Adversarial Sequences

[Bullet list of multi-step operation sequences that exploit domain-specific
gaps between state-changing and state-reading operations.]

- **[sequence description]** — [what coupled state could break?]
- ...

## Domain-Specific Coupled State Patterns

| Pattern | State A | State B (coupled) | Common gap |
|---------|---------|-------------------|------------|
| ... | ... | ... | ... |

## Domain-Specific Red Flags

[Additional red flags beyond the core-rules.md checklist,
specific to this domain.]

- [ ] [Red flag specific to this domain]
- ...
```

## Pattern Categories to Discover

Researchers must investigate these categories for the target domain:

### 1. Coupled State Patterns
State variables that must stay synchronized. Look for:
- Values computed from other values (caches, accumulators, summaries)
- Bidirectional maps or indexes
- Cross-component state that represents the same logical entity
- Status fields with dependent invariants

### 2. Adversarial Sequences
Multi-step operation sequences that exploit gaps. Look for:
- Operations that change an accounting base followed by operations that read it
- Partial operations (partial withdraw, partial close) that leave coupled state inconsistent
- Interleaved operations from different actors on shared state
- Operations valid individually but dangerous in combination

### 3. Path-Dependent Accumulators
Global accumulators where the order of operations affects the result. Look for:
- Fee/reward accumulators updated per-operation where accumulated value changes between operations
- Running totals that don't normalize against a changing denominator
- Interest/rate accumulators that compound differently based on operation ordering

### 4. Domain-Specific Invariants
Correctness properties unique to this domain. Look for:
- Conservation laws (total supply, total stake, sum of balances)
- Ordering constraints (operation A must precede operation B)
- Access control boundaries (who can trigger what state transitions)
- Lifecycle state machines (valid transitions, terminal states)

### 5. Masking Patterns
Defensive code that hides broken invariants. Look for:
- Clamps, min/max caps, saturating arithmetic on values that "should never" overflow
- Silent error swallowing in paths that update coupled state
- Fallback defaults that paper over missing or stale data

## Quality Rules

### Must
- Every pattern must reference actual code structures observed in the target codebase (types, functions, modules)
- Every adversarial sequence must describe concrete state transitions, not abstract possibilities
- Every coupled state pair must identify code that reads BOTH values together (the coupling point)
- Worked examples must show step-by-step state evolution with specific operations

### Must Not
- Do not copy patterns from other domains that don't apply (e.g., AMM patterns for a non-financial system)
- Do not invent code structures that don't exist in the codebase
- Do not report patterns without grounding them in observed code
- Do not produce generic advice — every bullet must be actionable for THIS codebase

### Grounding Test
For each pattern: "Could someone unfamiliar with this domain use this pattern to find a bug in THIS specific codebase?" If not, the pattern is too generic.

## Strategy Agent Output Format

The strategy agent produces a research plan, not patterns. Its output:

```markdown
# Domain Discovery Research Plan

## Domain Assessment
[What domain is this project in? What are the key value flows?]

## Research Topics

### Group 1 (parallel)

#### RT-1: [Topic Title]
- **Question:** [What specific domain pattern should this researcher investigate?]
- **Search scope:** [Which files/directories to focus on]
- **Keywords:** [Grep patterns to start with]
- **Category:** [coupled-state | adversarial-sequence | accumulator | invariant | masking]

#### RT-2: [Topic Title]
...

### Group 2 (parallel, after Group 1 if dependencies exist)
...

## Expected Output
[How many patterns are expected, what the domain-patterns.md should emphasize]
```

## Researcher Agent Output Format

Each researcher produces a single fragment file:

```markdown
# Research Topic: [Title]

## Observations
[What was found in the codebase relevant to this topic]

## Patterns Discovered

### [Pattern Name]
- **Category:** [coupled-state | adversarial-sequence | accumulator | invariant | masking]
- **State A:** [first state variable/component]
- **State B:** [coupled state variable/component]
- **Coupling point:** [code that reads both — file:line]
- **Gap:** [what operation breaks the coupling]

### Worked Example
[Step-by-step if applicable]

## Adversarial Sequences
- [sequence if applicable]

## Red Flags
- [ ] [domain-specific red flag if applicable]
```
