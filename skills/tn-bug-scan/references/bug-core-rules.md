# tn-bug-scan Core Rules

Shared reference for every tn-bug-scan phase agent. Read this file at the start of every phase.

## Framing

**This is a bug hunt, not an attacker kill-chain.** The adversary in this skill is *production* — real nodes running under real load, hitting corner cases the author never tested. Every question is framed as: **"what sequence of events makes this code crash, stall, diverge, or silently produce wrong state?"**

Do not ask "how does a malicious validator exploit this?". Ask "how does this fail under restart, under reorder, under partition, under epoch boundary, under concurrent load?". The same code paths are relevant, but the framing produces tickets (repro + failure mode) instead of attack paths.

## The 6 Bug-Hunter Rules

**RULE 0 — THE ITERATIVE LOOP IS MANDATORY.** Never run the Feynman interrogation and State Check as isolated one-shot passes. They must alternate — each pass feeding the next — until no new findings emerge. Convergence is proven by *absence of new bugs*, not by running N iterations.

**RULE 1 — FULL FIRST, TARGETED AFTER.** Phase 2 (Feynman) and Phase 3 (State) are full runs. Phase 4+ are targeted — only audit the delta from the previous pass. Never re-audit what was already cleared. Always go deeper on what's new.

**RULE 2 — EVERY COUPLED STATE PAIR GETS INTERROGATED.** The mapper finds coupled state. Feynman interrogates each pair: "What invariant links these? Is the invariant actually maintained by every mutation path? What happens on the path that drops it?"

**RULE 3 — EVERY FEYNMAN SUSPECT GETS STATE-TRACED.** When Feynman flags a line as SUSPECT, the state checker traces every state variable that line touches, maps all coupled dependencies, and checks whether the suspicion propagates into a real mutation gap.

**RULE 4 — PARTIAL OPERATIONS + ORDERING = GOLD.** The intersection of "partial state change" (state-check specialty) and "operation ordering" (Feynman Cat 2 & 7) is where the highest-value bugs live in a blockchain node. Epoch boundaries, mid-batch failures, and mid-flush restarts all live here.

**RULE 5 — DEFENSIVE CODE IS A SIGNAL, NOT A SOLUTION.** Saturating arithmetic, min/max clamps, `.unwrap_or_default()`, silent error swallowing — every one of these hides an invariant that's broken underneath. Feynman interrogates WHY the defense exists. The defense reveals the real bug.

**RULE 6 — EVIDENCE OR SILENCE.** No finding without: (a) failure mode, (b) repro conditions, (c) affected invariant, (d) root cause, (e) verification trace. If you cannot produce all five, do not report it. Speculative findings are noise, not value.

## Severity Calibration (Blockchain-Tuned)

Severity is calibrated for a BFT consensus node combining Narwhal/Bullshark consensus with EVM execution. A "Medium" in a typical web service may be "Critical" here if it causes validator disagreement.

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Consensus break, chain fork, validator divergence, unrecoverable state corruption, fund loss. The network halts, forks, or loses money. |
| **HIGH** | Node crash on production path, DoS of an honest validator, recoverable state corruption, silent wrong-state that persists across restarts. One validator goes down; network survives. |
| **MEDIUM** | Silent wrong-state that self-heals, rare panic vectors behind validation layers, mis-accounting under edge conditions, degraded liveness under specific load. |
| **LOW** | Defensive gaps, suboptimal error propagation, unreachable-but-sloppy panics, missing bounds check where type system provides partial guarantee. |
| **INFO** | Correctness-irrelevant style, dead code, naming. |

### Severity Decision Tree

```
1. Does the bug cause validators to disagree on output?
   YES → CRITICAL (consensus break)
   NO  → Continue

2. Does the bug crash the node from untrusted input (peer message, RPC, DB corruption)?
   YES → HIGH (node DoS)
   NO  → Continue

3. Does the bug corrupt state that persists across restarts?
   YES  → HIGH (recoverable) or CRITICAL (unrecoverable — evaluate case-by-case)
   NO   → Continue

4. Does the bug produce silent wrong output that downstream code reads?
   YES → MEDIUM (usually) — upgrade to HIGH if the wrong output influences consensus or funds
   NO  → Continue

5. Is the pattern an unreached panic/sloppy guard with no production reachability?
   YES → LOW
   NO  → INFO or not a finding
```

## Bug Categories

Every finding must be tagged with ONE primary category from this set:

| Category | Definition |
|----------|------------|
| **concurrency** | Data race, deadlock, lock-across-await, task cancellation bug, channel race |
| **determinism** | HashMap iteration, SystemTime/Instant in consensus path, non-seeded RNG, thread-scheduling-dependent result |
| **consensus** | Quorum miscount, signature/certificate validation gap, round/epoch boundary mishandling, equivocation not rejected |
| **state-atomicity** | Partial mutation on failure, coupled-state gap, mid-flush crash, missing transactional boundary |
| **panic-surface** | `.unwrap()` / `.expect()` on untrusted input, indexing without bounds check, integer overflow in release, `debug_assert!` used as a guard |
| **fork-risk** | Logic that behaves differently at different block heights or across upgrade without gating; a divergence-in-waiting |
| **error-propagation** | Silent `.map_err(|_|...)` context loss, `.ok()` swallowing, match arms that lose new variants, async-cancel-drops |

Secondary categories are allowed in the ticket body when a bug crosses boundaries (e.g., a panic on peer message = `panic-surface` primary, `consensus` secondary).

## Failure Modes

Every finding must declare ONE failure mode — the concrete observable symptom in production:

- **crash** — node panics / aborts
- **consensus-stall** — consensus stops making progress (no new commits)
- **chain-fork** — validators disagree on committed state
- **state-corruption** — on-disk / in-memory state violates its invariant
- **silent-wrong-state** — wrong result is returned, no error, downstream code proceeds
- **fund-flow-divergence** — balances / rewards / slashes computed inconsistently across validators
- **liveness-degradation** — node stays up but throughput collapses / tasks stall

## Anti-Hallucination Protocol

**Never:**
- Invent code that doesn't exist. Grep before citing.
- Claim a coupled pair without finding code that reads BOTH values together.
- Claim a function is missing an update without tracing its full call chain (hooks, extensions, middleware, trait defaults).
- Report a finding without: failure mode, repro conditions, affected invariant, root cause.
- Skip the Phase 4 feedback loop — cross-feed findings are the highest-value output.
- Present raw findings as verified results. Only the verifier (Phase 6) promotes findings to the verified report.

**Always:**
- Read the actual code before interrogating it.
- Verify coupled pairs by finding a read site for BOTH values.
- Trace internal calls for hidden updates (Rust: trait impls, Deref chains, macro-expanded code; Solidity: base contracts, modifiers, hooks).
- Check for lazy reconciliation patterns before reporting stale state (e.g., `updateReward()` called at the top of every function via modifier).
- Show exact file paths and line numbers.
- Run the feedback loop until convergence (or the 3-iteration safety maximum).
- Present ONLY verified findings in the final report.

## Red Flags Checklist

### From Feynman (logic-framed)
- [ ] A line whose purpose you cannot explain in one sentence
- [ ] An ordering choice with no justification
- [ ] A guard on funcA missing from funcB when both mutate the same state
- [ ] An implicit trust in caller / input / time / ordering
- [ ] State mutated AFTER an external call (reentrancy window) or AFTER a `.await` (cancellation window)
- [ ] Function behaves differently on second call due to first call's state change
- [ ] `.unwrap()` / `.expect()` on a value derived from untrusted input
- [ ] `debug_assert!` guarding an invariant that production depends on

### From State Check (coupling-framed)
- [ ] Function modifies State A but has no writes to coupled State B
- [ ] Two similar operations (transfer vs burn, withdraw vs liquidate) handle coupled state differently
- [ ] Partial operation exists but only full operation resets coupled state
- [ ] Defensive ternary / min() / saturating_sub between two coupled values (why could it underflow?)
- [ ] delete / reset of one mapping but not its paired mapping
- [ ] Loop accumulates into shared state without per-iteration coupled update
- [ ] Emergency / admin path bypasses normal coupled-state update
- [ ] On-disk write happens without the in-memory cache invalidation (or vice versa)

### From the Feedback Loop (highest confidence)
- [ ] Feynman ordering concern + state-check gap on the SAME function
- [ ] State-check masking code + Feynman explains WHY the underlying invariant is broken
- [ ] Feynman assumption about state freshness + state-check confirms the state IS stale after a specific mutation path
- [ ] Both auditors flag the SAME function from different angles
- [ ] A coupled pair found by state-check is interrogated by Feynman and reveals a missing ordering guard

### Telcoin-network-specific red flags
- [ ] `HashMap`/`HashSet` from `std::collections` iterated into a result that must agree across validators
- [ ] `SystemTime::now()` or `Instant::now()` influencing a consensus decision (not just a timeout)
- [ ] `parking_lot::Mutex` held across a `.await`
- [ ] `tokio::sync::mpsc::unbounded_channel` on a peer-facing handler
- [ ] `debug_assert!` guarding an invariant that real code reads
- [ ] `BTreeMap<Round, HashMap<AuthorityIdentifier, _>>` iterated to produce ordered output (outer is fine, inner is not)
- [ ] System-call ordering inside EVM block construction (slashes before incentives, etc.)
- [ ] Gossipsub / request-response handler panicking on malformed peer input
- [ ] Epoch-boundary code path that reads state before `merge_transitions` completes
- [ ] Storage write without a corresponding `durability::sync` on the critical path
