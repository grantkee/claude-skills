---
name: nemesis-og
description: "The Inescapable Auditor. Runs the full Feynman Auditor (Stage 1) and full State Inconsistency Auditor (Stage 2) as primary steps, then fuses their outputs in a feedback loop (Stage 3) to find bugs at the intersection that neither alone would catch. Language-agnostic. Triggers on /nemesis or nemesis audit."
---

# Nemesis — The Inescapable Auditor

An iterative back-and-forth loop where the Feynman Auditor and State Inconsistency Auditor run alternating passes — each pass informed by the previous pass's findings — until no new bugs surface.

**Pass 1 (Feynman)** — Run the **complete Feynman Auditor** (`.claude/skills/feynman-auditor/SKILL.md`). Every line questioned. Every ordering challenged. Every assumption exposed. Collect findings + suspects.

**Pass 2 (State)** — Run the **complete State Inconsistency Auditor** (`.claude/skills/state-inconsistency-auditor/SKILL.md`), **enriched by Pass 1's findings**. Feynman suspects become extra audit targets. Exposed assumptions reveal new coupled pairs to map. Collect findings + gaps.

**Pass 3+ (alternating, targeted)** — Re-run only on functions/state touched by the previous pass's new findings. Continue alternating until convergence (no new findings in a pass).

Feynman alone finds logic bugs but may miss state coupling gaps. State Mapper alone finds desync bugs but may miss WHY the state was designed that way. Nemesis runs them back and forth — each pass feeds the next. The bugs at the intersection are the ones neither would find alone.

**Language-agnostic.** Works on Solidity, Move, Rust, Go, C++, or anything else.

## When to Activate

- User says `/nemesis` or `nemesis audit` or `deep combined audit`
- User wants maximum-depth business logic + state inconsistency coverage
- When the codebase is complex enough that either auditor alone would miss cross-cutting bugs

## When NOT to Use

- Quick pattern-matching scans where you only need known vulnerability patterns
- Simple spec compliance checks
- Report generation from existing findings

---

## Core Rules

**RULE 0 — THE ITERATIVE LOOP IS MANDATORY.** Never run Feynman and State Mapper as isolated one-shot passes. They must alternate back and forth, each pass feeding the next, until no new findings emerge.

**RULE 1 — FULL FIRST, TARGETED AFTER.** Pass 1 (Feynman) and Pass 2 (State) are full skill runs. Pass 3+ are targeted — only audit the delta from the previous pass. Never re-audit what was already cleared. Always go deeper on what's new.

**RULE 2 — EVERY COUPLED PAIR GETS INTERROGATED.** The State Mapper finds pairs. Feynman interrogates each one: "Why are these coupled? What invariant links them? Is the invariant ACTUALLY maintained by every mutation path?"

**RULE 3 — EVERY FEYNMAN SUSPECT GETS STATE-TRACED.** When Feynman flags a line as SUSPECT, the State Mapper traces every state variable that line touches, maps all coupled dependencies, and checks if the suspicion propagates.

**RULE 4 — PARTIAL OPERATIONS + ORDERING = GOLD.** The intersection of "partial state change" (State Mapper's specialty) and "operation ordering" (Feynman's Category 2 & 7) is where the highest-value bugs live.

**RULE 5 — DEFENSIVE CODE IS A SIGNAL, NOT A SOLUTION.** When the State Mapper finds masking code (ternary clamps, min caps), Feynman interrogates WHY it exists. The mask reveals the invariant that's actually broken underneath.

**RULE 6 — EVIDENCE OR SILENCE.** No finding without: coupled pair, breaking operation, trigger sequence, downstream consequence, and verification.

---

## Language Adaptation

Detect the language and adapt terminology. The questions and methodology are universal.

| Concept | Solidity | Move | Rust | Go | C++ |
|---------|----------|------|------|----|-----|
| Module/unit | contract | module | crate/mod | package | class/namespace |
| Entry point | external/public fn | public fun | pub fn | Exported fn | public method |
| State storage | storage variables | global storage / resources | struct fields / state | struct fields / DB | member variables |
| Access guard | modifier | access control / friend | trait bound / #[cfg] | middleware / auth | access specifier |
| Mapping | mapping(k => v) | Table\<K, V\> | HashMap / BTreeMap | map[K]V | std::map |
| Delete | delete mapping[key] | table::remove | map.remove(&key) | delete(map, key) | map.erase(key) |
| Caller identity | msg.sender | &signer | caller / Context | ctx / request.User | this / session |
| Error/abort | revert / require | abort / assert! | panic! / Result::Err | error / panic | throw / exception |
| Checked math | 0.8+ auto / SafeMath | built-in overflow abort | checked_add | math/big | safe int libs |
| External call | .call() / interface | cross-module call | CPI (Solana) | RPC / HTTP | virtual call |
| Test framework | Foundry / Hardhat | Move Prover / aptos test | cargo test | go test | gtest / catch2 |

---

## Execution Pipeline

### Phase 0: Attacker Recon (BEFORE reading code)

Combine Feynman's attacker mindset with State Mapper's value tracking:

- **Q0.1 — ATTACK GOALS:** What's the WORST an attacker can achieve? List top 3-5 catastrophic outcomes. These drive the entire audit.
- **Q0.2 — NOVEL CODE:** What's NOT a fork of battle-tested code? Custom math, novel mechanisms, unique state machines = highest bug density.
- **Q0.3 — VALUE STORES:** Where does value actually sit? Map every module that holds funds, assets, accounting state. For each: what code path moves value OUT? What authorizes it?
- **Q0.4 — COMPLEX PATHS:** What's the most complex interaction path? Paths crossing 4+ modules with 3+ external calls = prime targets.
- **Q0.5 — COUPLED VALUE:** Which value stores have DEPENDENT accounting? For each value store from Q0.3, ask: "What other storage must stay in sync with this?" Build the initial coupling hypothesis BEFORE reading code.

**Output:** Attacker's Hit List + Initial Coupling Hypothesis — language detected, attack goals ranked, novel code flagged, value stores with suspected coupled state, complex paths, and priority targets ranked by frequency across all answers.

---

### Phase 1: Dual Mapping (Foundation)

Run both mapping operations simultaneously. They share the same codebase scan.

**1A — Function-State Matrix (Feynman foundation):**
For each module, list all entry points (public/exported/external functions), all state they read/write, all access guards applied, all internal functions called, all external calls made.

| Function | Reads | Writes | Guards | Internal Calls | External Calls |
|----------|-------|--------|--------|----------------|----------------|

**1B — Coupled State Dependency Map (State Mapper foundation):**
For every storage variable, ask: "What other storage values MUST change when this one changes?" Build the dependency graph. Look for: per-user balance vs accumulator/tracker/checkpoint, numerator vs denominator, position size vs derived values (health, rewards, shares), total/aggregate vs sum of components, cached computation vs inputs, index/accumulator vs last-snapshot per user.

**1C — Cross-Reference (THE NEMESIS DIFFERENCE):**
Overlay the two maps:

- For each coupled pair from 1B → find all functions from 1A that write to either side → mark which update BOTH sides vs only ONE side → functions updating only one side = PRIMARY AUDIT TARGETS
- For each function from 1A → list all state variables it writes → for each written variable, check 1B: is it part of a coupled pair? → if yes, does this function also write the coupled counterpart? → if no, mark as STATE GAP

**Output:** Unified Nemesis Map — functions x state x couplings x gaps. Example:

| Function | Writes A | Writes B | A-B Pair | Sync Status |
|----------|----------|----------|----------|-------------|
| deposit() | yes | yes | bal-chk | SYNCED |
| transfer() | yes | no | bal-chk | GAP -> Phase 3 |
| liquidate() | yes | no | bal-chk | GAP -> Phase 3 |

---

### Phase 2: Feynman Interrogation (Hunt Pass 1)

Apply all 7 Feynman Question Categories to every function, in priority order from Phase 0:

- **Category 1 — Purpose:** WHY is this line here? What breaks if deleted?
- **Category 2 — Ordering:** What if this line moves up/down? State gap window?
- **Category 3 — Consistency:** WHY does funcA have this guard but funcB doesn't?
- **Category 4 — Assumptions:** What is implicitly trusted about caller/data/state/time?
- **Category 5 — Boundaries:** First call, last call, double call, self-reference?
- **Category 6 — Return/Error:** Ignored returns, silent failures, fallthrough paths?
- **Category 7 — Call Reorder + Multi-Tx:** Swap external call before/after state update? Same function, different values, across time?

For each function, interrogate line-by-line. Each line gets a verdict: SOUND, SUSPECT, or VULNERABLE. Suspect lines get a specific scenario. All state variables touched are tagged for Phase 3.

**Category 7 deep checks** — for every external call in every function:

1. **Swap test:** Move the external call before/after state updates. Does it revert? If not, the original ordering may be exploitable.
2. **Callee power audit:** At the moment of the external call, what state is committed vs pending? What can the callee observe or manipulate?
3. **Multi-tx state corruption:** Call the function with value X, then again with value Y. Does the second call use stale state from the first? Does accumulated state from many calls create unreachable conditions?

**Feed forward:** Every SUSPECT verdict and every state variable touched by suspect code is passed to Phase 3 as an additional audit target.

---

### Phase 3: State Cross-Check (Hunt Pass 2)

The State Mapper runs its full analysis, ENRICHED by Feynman's Phase 2 output.

**3A — Mutation Matrix:** For each state variable (including new ones Feynman flagged), list every function that modifies it — direct writes, increments, decrements, deletions, indirect mutations (internal calls, hooks, callbacks), implicit changes (burns, rebases, external triggers). Mark whether each mutating function also updates coupled state.

**3B — Parallel Path Comparison:** Group functions that achieve similar outcomes (transfer vs burn, withdraw vs liquidate, partial vs full removal, direct vs wrapper, normal vs emergency/admin, single vs batch). For each group: do ALL paths update the SAME coupled state?

**3C — Operation Ordering Within Functions:** Trace the exact order of state changes in each function. At each step ask: Are all coupled pairs still consistent RIGHT HERE? Does step N use a value that step N-1 already invalidated? If an external call happens between steps, can the callee see inconsistent state?

**3D — Feynman-Enriched Targets:** For each SUSPECT from Phase 2, the State Mapper specifically checks: Is the suspect state variable part of a coupled pair? Does the suspect function update all coupled counterparts? Does the ordering concern from Feynman create a state gap the State Mapper can now measure? This is where the feedback loop produces findings that neither auditor would find alone.

**Feed forward:** Every GAP from Phase 3 is passed to Phase 4 for Feynman re-interrogation.

---

### Phase 4: The Nemesis Loop (core innovation)

The two auditors now interrogate EACH OTHER'S findings in a loop:

**Step A — State gaps -> Feynman re-interrogation:** For each GAP found in Phase 3, Feynman asks: "WHY doesn't [function] update [coupled state B] when it modifies [state A]?" / "What ASSUMPTION is the developer making about when [coupled state B] gets updated?" / "What DOWNSTREAM function reads [state B] and would produce a wrong result from the stale value?" / "Can an attacker CHOOSE a sequence that exploits this gap before [state B] gets reconciled?" If the gap is real: FINDING. If lazy reconciliation: FALSE POSITIVE. If a new coupled pair emerges: feed back to Step B.

**Step B — Feynman findings -> State dependency expansion:** For each Feynman SUSPECT/VULNERABLE verdict, State Mapper asks: "Does this suspicious line WRITE to a state that is part of a coupled pair I haven't mapped yet?" / "Does the ordering concern create a WINDOW where coupled state is inconsistent?" / "Does the assumption violation mean a coupled state's invariant is based on a false premise?" New coupling discovered: add to map, re-run 3A-3C for the new pair. No new coupling: Feynman finding stands alone.

**Step C — Masking code -> Joint interrogation:** For each defensive/masking pattern found (ternary clamps, min caps, try/catch, early returns): Feynman asks WHY it would ever underflow/overflow, what invariant is actually broken underneath. State Mapper asks which coupled pair's desync this mask is hiding, traces the pair to find the root mutation. Combined answer: the mask, the broken invariant, the root cause mutation, and the downstream impact.

**Step D — Convergence check:** Did Steps A-C produce ANY new coupled pairs not in the Phase 1 map, mutation paths not in the Phase 3 matrix, Feynman suspects not in the Phase 2 output, or masking patterns not previously flagged? If YES: loop back to Step A with expanded scope. If NO: converged, proceed to Phase 5. Safety maximum: 3 loop iterations to prevent runaway.

---

### Phase 5: Multi-Transaction Journey Tracing

Trace adversarial sequences that exploit findings from BOTH dimensions.

**Sequence template:**
1. Initial state (clean)
2. Operation that modifies State A (coupled to B)
3. [Optional: time passes / external state evolves]
4. Operation that SHOULD update B but DOESN'T (the gap)
5. [Optional: repeat steps 2-4 to compound the error]
6. Operation that reads BOTH A and B -> produces wrong result

**Adversarial sequences to always test:**
- Deposit -> partial withdraw -> claim rewards (rewards computed on which balance?)
- Stake -> unstake half -> restake -> unstake all (reward debt accumulated correctly?)
- Open position -> add collateral -> partial close -> health check (cached health factor updated?)
- Provide liquidity -> swaps happen -> remove liquidity (fee tracking correct?)
- Delegate votes -> transfer tokens -> vote (voting power reflects current balance?)
- Borrow -> partial repay -> borrow again -> check debt (interest accumulator rebased?)

For DeFi-specific patterns and a worked AMM example demonstrating path-dependent accumulator bugs, read `references/defi-patterns.md`.

**Generalize:** Any global accumulator (fees, rewards, interest) updated per-operation where the VALUE of what's accumulated changes between operations, and the accumulator doesn't normalize. Check: after N operations with varying sizes, does SUM(individual fees) == fee on AGGREGATE operation? If not: path-dependent accumulator, exploitable.

---

### Phase 6: Verification Gate (MANDATORY)

Every CRITICAL, HIGH, and MEDIUM finding must be verified.

**Method A — Deep Code Trace:** Read exact lines cited, trace complete call chain (caller -> callee -> downstream), check for mitigating code elsewhere (guards, hooks, lazy reconciliation), confirm scenario is reachable end-to-end.

**Method B — PoC Test:** Write test in project's native framework, execute the exact trigger sequence, assert state inconsistency after the breaking operation, assert incorrect result in the downstream operation.

**Method C — Hybrid** (trace + PoC) for complex multi-module findings.

**Common false positive patterns:**

1. **Hidden reconciliation** — coupled state IS updated, but through an internal call chain you missed (_beforeTokenTransfer hook, modifier that runs _updateReward before every function)
2. **Lazy evaluation** — coupled state is intentionally stale and reconciled on next READ, not on every WRITE; the desync is by design
3. **Immutable after init** — coupled state is set once and never needs updating because both sides are frozen after initialization
4. **Designed asymmetry** — the states are intentionally NOT coupled the way you assumed; read docs/comments before reporting
5. **Language safety** — finding claims overflow but the language aborts on overflow by default (Solidity >=0.8, Move, Rust debug)
6. **Severity inflation** — finding claims "value loss" but actual impact is "confusing error message" because a downstream check catches it
7. **Economic infeasibility** — the attack costs more than it gains; flash loans don't make everything free, compute actual profit

**Verification output per finding:**
- Finding ID and title
- Verification method used (A / B / C)
- Code trace paths and mitigations checked
- PoC result (test name, pass/fail, key output) if applicable
- Mitigating factors found (none or list)
- Verdict: TRUE POSITIVE [severity] / FALSE POSITIVE [reason] / DOWNGRADE [from -> to]

---

### Phase 7: Final Report

Save to: `.audit/findings/nemesis-verified.md`

**Report structure:**

- **Scope** — language, modules analyzed, function count, coupled pairs mapped, mutation paths traced, nemesis loop iterations
- **Nemesis Map** — the Phase 1 cross-reference (functions x state x couplings x gaps)
- **Verification Summary** — table with: ID, source (Feynman/State/Loop), coupled pair, breaking op, severity, verdict
- **Verified Findings (TRUE POSITIVES only)** — each finding includes:
  - Severity, source (which auditor or "Feedback Loop Step X"), verification method
  - Coupled pair and the invariant that must hold
  - The Feynman question that exposed it (exact quote)
  - The State Mapper gap that confirmed it (mutation matrix entry)
  - Breaking operation with file path and line number
  - Trigger sequence (step-by-step minimal adversarial sequence)
  - Consequence with concrete impact and numbers
  - Masking code (if present)
  - Verification evidence (code trace paths / PoC output)
  - Minimal fix
- **Feedback Loop Discoveries** — findings that ONLY emerged from cross-feed between auditors
- **False Positives Eliminated** — with explanation
- **Downgraded Findings** — with justification
- **Summary** — total functions, coupled pairs, loop iterations, raw findings by severity, feedback loop discovery count, verification results, final severity counts

Tag each finding with discovery path: "Feynman-only", "State-only", or "Cross-feed P[N]->P[M]".

Also save intermediate work to: `.audit/findings/nemesis-raw.md`

---

## Severity Classification

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Direct value loss, permanent DoS, or system insolvency. Exploitable now. |
| **HIGH** | Conditional value loss, privilege escalation, or broken core invariant |
| **MEDIUM** | Value leakage, griefing with cost, incorrect accounting, degraded functionality |
| **LOW** | Informational, cosmetic inconsistency, edge-case-only with no material impact |

---

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

---

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

---

## Execution Checklist

- [ ] Phase 0: Attacker recon (goals, novel code, value stores, coupling hypothesis)
- [ ] Phase 1A: Build Function-State Matrix
- [ ] Phase 1B: Build Coupled State Dependency Map
- [ ] Phase 1C: Cross-reference into Unified Nemesis Map
- [ ] Phase 2: Feynman interrogation (all 7 categories, priority order)
- [ ] Phase 2: Feed all SUSPECT verdicts to Phase 3
- [ ] Phase 3A: Build Mutation Matrix (enriched by Feynman suspects)
- [ ] Phase 3B: Parallel Path Comparison
- [ ] Phase 3C: Operation Ordering check
- [ ] Phase 3D: Feynman-Enriched Target analysis
- [ ] Phase 4: Nemesis Loop — Step A (state gaps -> Feynman), Step B (findings -> state expansion), Step C (masking code -> joint), Step D (convergence check, max 3 iterations)
- [ ] Phase 5: Multi-transaction journey tracing (adversarial sequences)
- [ ] Phase 6: Verify all C/H/M findings (code trace + PoC)
- [ ] Phase 6: Eliminate false positives
- [ ] Phase 7: Save to .audit/findings/nemesis-verified.md
- [ ] Phase 7: Present ONLY verified findings

---

## Post-Audit Actions

| Scenario | Action |
|----------|--------|
| Need deeper protocol context | Re-read the relevant contracts and documentation |
| Finding needs formal report | Write up with severity, trigger sequence, PoC, and fix |
| Need exploit validation | Write a PoC test in the project's native framework |
| Uncertain about design intent | Check NatSpec, comments, and project documentation |
