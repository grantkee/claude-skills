# Bug Ticket Format

Reference for Phase 7 (reporter). Every verified finding in `tn-bug-scan-verified.md` must follow this exact template. Missing fields = incomplete ticket.

## Required Template

```markdown
### [SEVERITY] [CATEGORY] <Title>

- **Location:** `crate/src/path.rs:LINE` (and related files: `other.rs:LINE`, `sol/file.sol:LINE`)
- **Category:** concurrency | determinism | consensus | state-atomicity | panic-surface | fork-risk | error-propagation
- **Secondary categories:** (optional — use when the bug crosses boundaries, e.g., `panic-surface, consensus`)
- **Failure mode:** crash | consensus-stall | chain-fork | state-corruption | silent-wrong-state | fund-flow-divergence | liveness-degradation
- **Repro conditions:** <concrete trigger sequence — ordered events, specific state, specific timing>
- **Affected invariant:** <the invariant that breaks, named from the relevant tn-domain-* skill where possible (e.g., `tn-domain-consensus: certificate digest covers all inputs`)>
- **Root cause:** <one-paragraph reasoning trace — cites Feynman category and/or state gap ID>
- **Recommended fix:** <approach, not a full patch>
- **Confidence:** HIGH | MEDIUM | LOW
- **Source:** <Feynman-only | State-only | Cross-feed P[N]→P[M] | Scenario>
- **Discovery path:** <which phase first surfaced this and why>
```

## Field Rules

### Title
- Start with a verb or concrete noun. No "possible", "potential", "may" — the ticket IS the claim.
- Good: "Vote aggregator accepts duplicate votes from same authority in same round"
- Good: "Certificate fetcher unbounded queue OOMs under peer flood"
- Bad: "Potential issue with certificate validation"

### Severity
- From `bug-core-rules.md` — CRITICAL / HIGH / MEDIUM / LOW / INFO.
- Do NOT inflate. If downgraded by the verifier, record the pre-verification severity in parentheses: `HIGH (was CRITICAL)`.

### Location
- Always `file_path:line_number` format. Prefer `crate/src/path.rs:42` over just `path.rs`.
- When multiple lines matter, list the primary and up to 3 related: `primary.rs:42 (related: other.rs:100, sol/File.sol:55)`.

### Category
- Exactly one primary category from the 7-item enum. Arbitrary combinations are NOT allowed.
- If the bug is genuinely cross-category, pick the one whose MITIGATION drives the fix.

### Failure mode
- Exactly one from the 7-item enum. This is the observable symptom in production.
- Rule: if you can't name the failure mode concretely, the finding isn't ready — send it back to Phase 6 or drop it.

### Repro conditions
- A concrete event sequence. **Not** a vague "under load" or "if the message is malformed".
- Good: "Validator A receives round-N batch from peer B while local state is at round N+1; local epoch manager has already called merge_transitions; the round-N batch applies against post-transition state."
- Good: "Two peers send different headers from authority X in round 42 within 100ms; the aggregator stores both; leader election later picks inconsistently."
- Bad: "Under high concurrency."
- Bad: "When input is invalid."

### Affected invariant
- Name the invariant. Cross-reference the relevant `tn-domain-*` skill where the invariant lives.
- Good: "tn-domain-consensus — certificate digest must cover every transaction in the batch"
- Good: "tn-domain-storage — consensus DB and reth DB writes must commit atomically across the pair"
- Good (no domain skill match): "Local invariant: `balance.sum() == total_supply` at the end of every block"

### Root cause
- One paragraph. What is the actual flaw? Cite the Feynman category that exposed it, the state gap ID that confirmed it, or both.
- Good: "Cat 2 (ordering): the state write happens after the external call, so the callee observes stale state. State gap SG-003 confirms no other path reconciles. The only reconciliation happens on epoch close, which is too late for in-round consumers."

### Recommended fix
- APPROACH, not a patch. One or two sentences describing what to change.
- Good: "Move the state write before the external call; add a rollback path that reverts the write if the call fails."
- Good: "Replace `HashMap` with `BTreeMap<AuthorityIdentifier, Vote>` so iteration order is deterministic across validators."
- Bad: "Fix the bug." / "Add validation."

### Confidence
- HIGH — verifier ran a PoC test OR traced the full path end-to-end with zero open questions.
- MEDIUM — verifier traced the path but some invariants on callers are assumed rather than verified.
- LOW — verifier confirmed the pattern but reachability from production input involves assumptions.

### Source
- `Feynman-only` — found in Phase 2 with no state-check involvement.
- `State-only` — found in Phase 3 with no Feynman suspicion.
- `Cross-feed P[N]→P[M]` — found in the Phase 4 feedback loop via cross-feed between Feynman and state-check. **Highest-value findings come from this source.**
- `Scenario` — only surfaced when Phase 5 traced a multi-event sequence.

### Discovery path
- Narrate briefly: which phase first surfaced it, which phase confirmed it, and what the cross-feed looked like.
- Good: "Phase 2 flagged lock-across-await in `certifier.rs:187`. Phase 3 found no coupled-state gap on its own. Phase 4 cross-feed: the lock-across-await creates a window during which the vote aggregator's HashMap is inconsistent with the certified-height cache. Phase 5 built the partition-heal scenario."

## Examples

### Example 1 — Cross-feed critical finding

```markdown
### [CRITICAL] [determinism] Vote aggregator HashMap iteration produces validator-dependent certificate digest

- **Location:** `crates/consensus/primary/src/aggregators/votes.rs:142` (related: `crates/consensus/primary/src/certifier.rs:89`)
- **Category:** determinism
- **Secondary categories:** consensus
- **Failure mode:** chain-fork
- **Repro conditions:** Two validators each receive the same set of votes (for round 42, header digest D) from the committee in the same order. Each aggregator inserts the votes into a `HashMap<AuthorityIdentifier, Signature>`. When the threshold is reached, the certifier calls `aggregator.finalize()` which iterates the HashMap to build a `Vec<Signature>` and hashes it into the certificate digest. Iteration order differs across validator processes (different RandomState seeds). The two certificates have identical votes but different digests.
- **Affected invariant:** tn-domain-consensus — identical vote sets must produce identical certificate digests on every honest validator.
- **Root cause:** Feynman Cat 2 (ordering) flagged the finalize() iteration as unexplained. State-check gap SG-007 confirmed the HashMap is the only ordering source and no sort step precedes the digest hash. Cross-feed: the finalize() is called before the certificate is stored, so once the digests diverge, no reconciliation path exists.
- **Recommended fix:** Replace `HashMap<AuthorityIdentifier, Signature>` with `BTreeMap` (AuthorityIdentifier implements Ord) so iteration is deterministic. Alternative: collect to Vec and sort by AuthorityIdentifier before hashing.
- **Confidence:** HIGH
- **Source:** Cross-feed P2→P3
- **Discovery path:** Phase 2 suspected the HashMap iteration; Phase 3 confirmed no upstream sort; Phase 4 first iteration surfaced the downstream digest dependency; Phase 5 built the two-validator partition scenario showing two certificates can be produced; Phase 6 verified by tracing finalize() end-to-end.
```

### Example 2 — Panic surface

```markdown
### [HIGH] [panic-surface] Certificate fetcher unwraps deserialization of peer response

- **Location:** `crates/state-sync/src/cert_manager.rs:412`
- **Category:** panic-surface
- **Failure mode:** crash
- **Repro conditions:** A peer responds to a `GetCertificates` request with bytes that do not deserialize as `Vec<Certificate>`. The handler calls `bincode::deserialize(&bytes).unwrap()`, which panics. The panic propagates out of the tokio task, aborting the fetcher. Legitimate catchup stalls until the node is restarted.
- **Affected invariant:** tn-domain-networking — peer messages are untrusted input; every deserialization must return a Result to the caller.
- **Root cause:** Direct `.unwrap()` on untrusted peer bytes. Feynman Cat 6 (return/error) flagged it immediately; no state-check contribution.
- **Recommended fix:** Replace `.unwrap()` with `?` and propagate a `StateSyncError::MalformedResponse` up to the caller, which already has a peer-scoring hook.
- **Confidence:** HIGH
- **Source:** Feynman-only
- **Discovery path:** Phase 2 found the unwrap on untrusted input; Phase 6 verified the peer-scoring hook exists at the caller and the conversion is safe.
```

### Example 3 — State atomicity

```markdown
### [HIGH] [state-atomicity] Partial epoch transition on panic between merge_transitions and committee update

- **Location:** `crates/tn-reth/src/system_calls.rs:203` (related: `crates/consensus/primary/src/epoch/manager.rs:88`)
- **Category:** state-atomicity
- **Failure mode:** state-corruption
- **Repro conditions:** `merge_transitions` successfully applies slashes and incentives to EVM state. The Rust-side epoch manager then updates its cached `Committee` from the `ConsensusRegistry` contract. Before the cache update, the process panics (OOM, hardware fault, or a later bug). On restart, the EVM state is post-transition but the cached committee is read from memory and re-initialized from the registry during startup — however, a different code path rebuilds the committee from the pre-transition epoch record in the consensus DB, producing a committee that does not match the EVM state's current authorities.
- **Affected invariant:** tn-domain-epoch — EVM-side committee (post merge_transitions) and Rust-side cached Committee must stay in sync at every quiescent point.
- **Root cause:** The two mutations are in separate transactions / separate code paths with no unified commit point. Feynman Cat 2 (ordering) flagged the gap; state-check gap SG-012 confirmed no rollback path for the EVM half if the Rust half fails.
- **Recommended fix:** Persist a "transition in progress" marker to the consensus DB before merge_transitions runs; on restart, if the marker is set, complete or roll back the Rust-side update to match EVM state.
- **Confidence:** MEDIUM
- **Source:** Cross-feed P3→P2
- **Discovery path:** Phase 3 found the coupled pair (EVM committee ↔ Rust cache) with no atomic commit; Phase 4 cross-feed asked Feynman why the ordering was chosen; no justification found; Phase 5 built the mid-transition-panic scenario.
```

## Final Ticket Checklist

Before accepting a ticket in the verified report:

- [ ] All 10 required fields present (title, severity, location, category, failure mode, repro, invariant, root cause, fix, confidence, source, discovery path)
- [ ] Severity is one of the 5 enum values
- [ ] Category is one of the 7 enum values (primary)
- [ ] Failure mode is one of the 7 enum values
- [ ] `file_path:line_number` is present for every code reference
- [ ] Repro conditions are concrete (specific functions, specific state, specific timing) — not "under load"
- [ ] Root cause cites either a Feynman category, a state gap ID, or both
- [ ] Fix is an approach, not a handwave
- [ ] Source tag matches the phase artifacts (cross-feed requires evidence in Phase 4 output)
