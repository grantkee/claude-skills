name: nemesis-auditor
description: >-
  Iterative deep-logic security audit agent combining Feynman first-principles
  questioning and State Inconsistency analysis in an alternating feedback loop.
  Language-agnostic — works on Solidity, Move, Rust, Go, C++, Python,
  TypeScript, or any codebase. Use when the user says "nemesis", "nemesis
  audit", "deep audit", "security audit", "deep combined audit", or wants
  maximum-depth business logic and state inconsistency coverage.
---

# N E M E S I S — The Inescapable Auditor

An iterative back-and-forth loop between two audit methodologies. Each pass feeds the next until no new bugs surface.

| Pass | Methodology | What It Finds |
|------|-------------|---------------|
| 1 | **Feynman Auditor** | Business logic bugs via first-principles questioning |
| 2 | **State Inconsistency Auditor** | Coupled state desync bugs via mutation path mapping |
| 3+ | **Alternating targeted passes** | Cross-feed findings — bugs neither methodology catches alone |

Loop runs until **convergence** (no new findings) or max 6 passes.

## Sub-methodology references

- For the full Feynman Auditor methodology, read [feynman-auditor.md](feynman-auditor.md)
- For the full State Inconsistency Auditor methodology, read [state-inconsistency-auditor.md](state-inconsistency-auditor.md)

Read these references as needed during execution — don't load them upfront.

---

## When to Use

- User wants maximum-depth business logic + state inconsistency coverage
- Codebase is complex enough that either methodology alone would miss cross-cutting bugs
- User explicitly requests a nemesis / deep combined audit

## When NOT to Use

- Quick pattern-matching scans for known vulnerability classes
- Simple spec compliance checks
- Report generation from existing findings

---

## Language Adaptation

Detect the language and adapt. The questions and methodology are universal.

| Concept | Solidity | Move | Rust | Go | C++ |
|---------|----------|------|------|----|-----|
| Module/unit | contract | module | crate/mod | package | class/namespace |
| Entry point | external/public fn | public fun | pub fn | Exported fn | public method |
| State storage | storage variables | global storage / resources | struct fields / state | struct fields / DB | member variables |
| Access guard | modifier | access control / friend | trait bound / #[cfg] | middleware / auth | access specifier |
| Error/abort | revert / require | abort / assert! | panic! / Result::Err | error / panic | throw / exception |
| External call | .call() / interface | cross-module call | CPI (Solana) | RPC / HTTP | virtual call |

---

## Core Rules

```
RULE 0: THE ITERATIVE LOOP IS MANDATORY
Never run Feynman and State as isolated one-shot passes.
They MUST alternate. Each pass feeds the next.

RULE 1: FULL FIRST, TARGETED AFTER
Pass 1 (Feynman) and Pass 2 (State) are FULL runs.
Pass 3+ are TARGETED — only audit the delta from the previous pass.

RULE 2: EVERY COUPLED PAIR GETS INTERROGATED
State finds pairs. Feynman interrogates each one.

RULE 3: EVERY FEYNMAN SUSPECT GETS STATE-TRACED
When Feynman flags a line as SUSPECT, State traces every
state variable it touches and checks if suspicion propagates.

RULE 4: PARTIAL OPERATIONS + ORDERING = GOLD
Intersection of "partial state change" and "operation ordering"
is where the highest-value bugs live.

RULE 5: DEFENSIVE CODE IS A SIGNAL, NOT A SOLUTION
Masking code (ternary clamps, min caps) reveals broken invariants.

RULE 6: EVIDENCE OR SILENCE
No finding without: coupled pair, breaking operation, trigger
sequence, downstream consequence, and verification.
```

---

## Execution Pipeline

### Phase 0: Attacker Recon (BEFORE reading code)

Answer these questions to build the hit list:

```
Q0.1: ATTACK GOALS — Top 3-5 catastrophic outcomes an attacker can achieve
Q0.2: NOVEL CODE — What's NOT a fork of battle-tested code?
Q0.3: VALUE STORES — Where does value sit? What moves it out? What authorizes it?
Q0.4: COMPLEX PATHS — Paths crossing 4+ modules with 3+ external calls
Q0.5: COUPLED VALUE — Which value stores have dependent accounting?
```

**Output:** Attacker's Hit List + Initial Coupling Hypothesis with priority targets.

### Phase 1: Dual Mapping (Foundation)

Run both mapping operations on the same codebase scan:

**1A: Function-State Matrix** (Feynman foundation)
- For each module: ALL entry points, state read/write, access guards, internal calls, external calls

**1B: Coupled State Dependency Map** (State foundation)
- For every storage variable: "What other storage values MUST change when this changes?"
- Map the dependency graph with invariant relationships

**1C: Cross-Reference** (THE NEMESIS DIFFERENCE)
- Overlay the two maps
- For each coupled pair → find ALL functions that write to either side
- Mark which functions update BOTH sides vs only ONE side
- Functions updating only ONE side = PRIMARY AUDIT TARGETS

Output: Unified Nemesis Map — functions x state x couplings x gaps.

### Phase 2: Feynman Interrogation (Pass 1 — Full Run)

Read [feynman-auditor.md](feynman-auditor.md) and execute the complete Feynman pipeline.

Apply all 7 question categories to every function in priority order:
1. Purpose — WHY is this line here?
2. Ordering — What if this line moves?
3. Consistency — WHY does A have it but B doesn't?
4. Assumptions — What is implicitly trusted?
5. Boundaries — First call, last call, double call, self-reference?
6. Return/Error — Ignored returns, silent failures?
7. Call Reorder + Multi-Tx — Swap external call timing? State corruption across time?

For every SUSPECT verdict: feed the state variables touched to Phase 3.

Save findings to: `.audit/findings/feynman-pass1.md`

### Phase 3: State Cross-Check (Pass 2 — Full Run, Enriched)

Read [state-inconsistency-auditor.md](state-inconsistency-auditor.md) and execute the complete State pipeline, ENRICHED by Pass 1's output:

- Feynman SUSPECTS → extra state audit targets
- Exposed assumptions → reveal NEW coupled pairs
- Ordering concerns → check if state gap exists at flagged point
- Function-State Matrix → base for Mutation Matrix

Execute: Mutation Matrix → Parallel Path Comparison → Operation Ordering → Feynman-Enriched Targets.

Save findings to: `.audit/findings/state-pass2.md`

### Phase 4: The Nemesis Loop (Feedback — core innovation)

```
LOOP {
  STEP A: State gaps → Feynman re-interrogation
    For each GAP: WHY doesn't [function] update [coupled state B]?
    What assumption led to this? What breaks downstream?

  STEP B: Feynman findings → State dependency expansion
    For each SUSPECT/VULNERABLE: Does this write to an unmapped coupled pair?
    Does the ordering concern create a consistency window?

  STEP C: Masking code → Joint interrogation
    Feynman asks: WHY would this underflow? What invariant is broken?
    State asks: Which coupled pair's desync is this mask hiding?

  STEP D: Convergence check
    New findings/pairs/suspects/root causes? → loop back
    Nothing new? → converged. Max 3 loop iterations.
}
```

Save targeted pass findings to: `.audit/findings/feynman-pass3.md`, `.audit/findings/state-pass4.md`, etc.

### Phase 5: Multi-Transaction Journey Tracing

Construct minimal trigger sequences for each finding:
1. Initial clean state
2. Operation modifying State A (coupled to B)
3. Operation that SHOULD update B but DOESN'T (the gap)
4. Operation reading BOTH A and B → wrong result

Always test adversarial sequences: deposit→partial withdraw→claim, stake→unstake half→restake→unstake all, open position→add collateral→partial close→health check, etc.

### Phase 6: Verification Gate (MANDATORY)

Every CRITICAL, HIGH, and MEDIUM finding MUST be verified.

**Method A: Deep Code Trace** — Read exact lines, trace call chain, check mitigating code, confirm reachability.
**Method B: PoC Test** — Write test in project's native framework, execute trigger sequence, assert inconsistency.
**Method C: Hybrid** — Trace + PoC for complex multi-module findings.

Common false positive patterns:
1. Hidden reconciliation (hooks, modifiers, base classes)
2. Lazy evaluation (intentional stale state, reconciled on read)
3. Immutable after init
4. Designed asymmetry
5. Language safety (auto-overflow abort in Solidity >=0.8, Move, Rust)
6. Severity inflation
7. Economic infeasibility

### Phase 7: Final Report

Save to: `.audit/findings/nemesis-verified.md`

```markdown
# N E M E S I S — Verified Findings

## Scope
- Language, modules, functions, coupled pairs, mutation paths, loop iterations

## Nemesis Map
[Functions x state x couplings x gaps]

## Verification Summary
| ID | Source | Coupled Pair | Breaking Op | Severity | Verdict |

## Verified Findings (TRUE POSITIVES only)

### Finding NM-XXX: [Title]
**Severity:** CRITICAL | HIGH | MEDIUM | LOW
**Source:** [Which methodology, or "Feedback Loop Step X"]
**Coupled Pair:** State A ↔ State B
**Invariant:** [Relationship that must hold]
**Breaking Operation:** `functionName()` at `File:LXXX`
**Trigger Sequence:** [Step-by-step]
**Consequence:** [What breaks, with concrete numbers]
**Fix:** [Minimal code change]

## Feedback Loop Discoveries
[Findings that ONLY emerged from cross-feed]

## False Positives Eliminated
## Downgraded Findings
## Summary
```

---

## Severity Classification

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Direct value loss, permanent DoS, system insolvency. Exploitable now. |
| **HIGH** | Conditional value loss, privilege escalation, broken core invariant |
| **MEDIUM** | Value leakage, griefing with cost, incorrect accounting, degraded functionality |
| **LOW** | Informational, cosmetic inconsistency, edge-case-only with no material impact |

---

## Red Flags Checklist (Combined)

```
FEYNMAN:
- [ ] A line whose PURPOSE you cannot explain
- [ ] An ordering choice with no clear justification
- [ ] A guard on funcA missing from funcB (same state)
- [ ] Implicit trust assumption about caller/data/state/time
- [ ] External call with state updates AFTER it
- [ ] Function behaves differently on 2nd call due to 1st call's state change

STATE:
- [ ] Function modifies State A but no writes to coupled State B
- [ ] Two similar operations handle coupled state differently
- [ ] Claim/collect runs before reduce/remove with no reconciliation
- [ ] Partial operation exists but only full operation resets coupled state
- [ ] Defensive ternary/min() between coupled values (WHY underflow?)
- [ ] delete/reset of one mapping but not its paired mapping
- [ ] Emergency/admin function bypasses normal state update path

FEEDBACK LOOP:
- [ ] Feynman ordering concern + State gap in SAME function → compound finding
- [ ] State masking code + Feynman explains broken invariant → root cause
- [ ] Feynman stale-state assumption + State confirms stale after mutation path
- [ ] Both methodologies flag SAME function → highest confidence finding
```

---

## Anti-Hallucination Protocol

```
NEVER:
- Invent code that doesn't exist in the codebase
- Assume a coupled pair without finding code that reads BOTH values together
- Claim a function is missing an update without tracing its full call chain
- Report a finding without exact code, trigger sequence, AND consequence
- Force Solidity terminology onto non-Solidity code
- Skip the feedback loop — it's where the highest-value bugs emerge
- Present raw findings as verified results

ALWAYS:
- Read actual code before questioning it
- Verify coupled pairs by finding code that reads BOTH values
- Trace internal calls for hidden updates (hooks, modifiers, base classes)
- Check for lazy reconciliation patterns before reporting stale state
- Show exact file paths and line numbers
- Run the feedback loop until convergence
- Present ONLY verified findings in the final report
```

---

## Quick-Start Checklist

```
- [ ] Phase 0: Attacker recon (goals, novel code, value stores, coupling hypothesis)
- [ ] Phase 1A: Build Function-State Matrix
- [ ] Phase 1B: Build Coupled State Dependency Map
- [ ] Phase 1C: Cross-reference → Unified Nemesis Map
- [ ] Phase 2: Feynman interrogation (read feynman-auditor.md, all 7 categories)
- [ ] Phase 2: Feed SUSPECT verdicts to Phase 3
- [ ] Phase 3: State cross-check (read state-inconsistency-auditor.md, enriched)
- [ ] Phase 4: THE NEMESIS LOOP (Steps A-D, max 3 iterations)
- [ ] Phase 5: Multi-transaction journey tracing
- [ ] Phase 6: Verify ALL C/H/M findings (code trace + PoC)
- [ ] Phase 7: Save to .audit/findings/nemesis-verified.md
- [ ] Phase 7: Present ONLY verified findings
```
