# Nemesis Core Rules

Shared reference for all nemesis-scan phase agents. Read this file at the start of every phase.

## The 6 Rules

**RULE 0 — THE ITERATIVE LOOP IS MANDATORY.** Never run Feynman and State Mapper as isolated one-shot passes. They must alternate back and forth, each pass feeding the next, until no new findings emerge.

**RULE 1 — FULL FIRST, TARGETED AFTER.** Pass 1 (Feynman) and Pass 2 (State) are full skill runs. Pass 3+ are targeted — only audit the delta from the previous pass. Never re-audit what was already cleared. Always go deeper on what's new.

**RULE 2 — EVERY COUPLED PAIR GETS INTERROGATED.** The State Mapper finds pairs. Feynman interrogates each one: "Why are these coupled? What invariant links them? Is the invariant ACTUALLY maintained by every mutation path?"

**RULE 3 — EVERY FEYNMAN SUSPECT GETS STATE-TRACED.** When Feynman flags a line as SUSPECT, the State Mapper traces every state variable that line touches, maps all coupled dependencies, and checks if the suspicion propagates.

**RULE 4 — PARTIAL OPERATIONS + ORDERING = GOLD.** The intersection of "partial state change" (State Mapper's specialty) and "operation ordering" (Feynman's Category 2 & 7) is where the highest-value bugs live.

**RULE 5 — DEFENSIVE CODE IS A SIGNAL, NOT A SOLUTION.** When the State Mapper finds masking code (ternary clamps, min caps), Feynman interrogates WHY it exists. The mask reveals the invariant that's actually broken underneath.

**RULE 6 — EVIDENCE OR SILENCE.** No finding without: coupled pair, breaking operation, trigger sequence, downstream consequence, and verification.

## Severity Classification

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Direct value loss, permanent DoS, or system insolvency. Exploitable now. |
| **HIGH** | Conditional value loss, privilege escalation, or broken core invariant |
| **MEDIUM** | Value leakage, griefing with cost, incorrect accounting, degraded functionality |
| **LOW** | Informational, cosmetic inconsistency, edge-case-only with no material impact |

## Anti-Hallucination Protocol

**Never:**
- Invent code that doesn't exist in the codebase
- Assume a coupled pair without finding code that reads BOTH values together
- Claim a function is missing an update without tracing its full call chain
- Report a finding without the exact code, trigger sequence, AND consequence
- Force Solidity terminology onto non-Solidity code
- Skip the feedback loop (Phase 4) — it's where the highest-value bugs emerge
- Present raw findings as verified results

**Always:**
- Read actual code before questioning it
- Verify coupled pairs by finding code that reads BOTH values
- Trace internal calls for hidden updates (hooks, modifiers, base classes)
- Check for lazy reconciliation patterns before reporting stale state
- Show exact file paths and line numbers
- Run the feedback loop until convergence
- Present ONLY verified findings in the final report

## Red Flags Checklist

**From Feynman:**
- [ ] A line of code whose PURPOSE you cannot explain
- [ ] An ordering choice with no clear justification
- [ ] A guard on funcA that's missing from funcB (same state)
- [ ] An implicit trust assumption about caller/data/state/time
- [ ] External call with state updates AFTER it (stale state window)
- [ ] Function behaves differently on 2nd call due to 1st call's state change

**From State Mapper:**
- [ ] Function modifies State A but has no writes to coupled State B
- [ ] Two similar operations handle coupled state differently
- [ ] Claim/collect runs before reduce/remove with no reconciliation
- [ ] Partial operation exists but only full operation resets coupled state
- [ ] Defensive ternary/min() between two coupled values (WHY underflow?)
- [ ] delete/reset of one mapping but not its paired mapping
- [ ] Loop accumulates into shared state without per-iteration adjustment
- [ ] Emergency/admin function bypasses normal state update path

**From the Feedback Loop (highest confidence):**
- [ ] Feynman ordering concern + State Mapper gap in the SAME function
- [ ] State Mapper masking code + Feynman explains WHY the invariant is broken underneath
- [ ] Feynman assumption about state freshness + State Mapper confirms the state IS stale after a specific mutation path
- [ ] Both auditors flag the SAME function from different angles
