# Nemesis-Scan Refinement Suggestions

_Evaluation date: 2026-04-12_

## Flow Trace Results

Traced the generic nemesis-scan from invocation through the full pipeline:

**SKILL.md (step 6) -> nemesis-orchestrator -> Phase -1 -> Phases 0-7**

1. **SKILL.md -> orchestrator handoff:** The SKILL.md prompt tells the orchestrator that `References are at: [absolute path to skills/nemesis-scan/references/]`. The orchestrator (agents/nemesis-orchestrator.md) reads this as the `Skill references path` input and uses it to resolve `references/core-rules.md`, `references/language-adaptation.md`, and `references/research-guide.md`. This chain is intact.

2. **Phase -1a (orchestrator -> nemesis-strategy):** The orchestrator passes `research-guide.md` to the strategy agent. However, the orchestrator prompt (line 88-89) says to pass "research-guide: references/research-guide.md" as a relative path. The strategy agent (agents/nemesis-strategy.md) expects a "path to `references/research-guide.md`" in its input. **Gap: the orchestrator never explicitly resolves relative to absolute.** In practice the orchestrator's prompt example uses `references/research-guide.md` as a relative reference, but it received the absolute references path in step 4 of its setup. The conversion from absolute base + relative file is implicit -- works but fragile.

3. **Phase -1b (orchestrator -> nemesis-researcher):** Same pattern. The orchestrator passes `research-guide: references/research-guide.md` to each researcher. The researcher agent expects "path to `references/research-guide.md`". Chain works but relies on the same implicit resolution.

4. **Phase -1c (orchestrator compiles domain-patterns.md):** The orchestrator reads fragments from `.audit/nemesis-scan/research/RT-*.md` and writes `.audit/domain-patterns.md`. This is well-specified and the cache metadata format matches what SKILL.md checks in step 4.

5. **Phases 0-7 agent spawns:** The orchestrator references agents by name: `nemesis-recon`, `nemesis-mapper`, `nemesis-feynman`, `nemesis-state-check`, `nemesis-journey`, `nemesis-verifier`, `nemesis-reporter`. All exist in `agents/`. Each receives references path, domain patterns path, and phase output paths. Chain is intact.

6. **Missing agent reference in orchestrator prompt:** The SKILL.md prompt to the orchestrator says "Phase 4: feedback loop (max 3 iterations)" but the orchestrator itself runs Phase 4 directly (not as a spawned agent). This is correct behavior -- the orchestrator IS the Phase 4 executor. No gap here, but the SKILL.md prompt phrasing could confuse readers since all other phases name agents.

7. **Gap: SKILL.md does not instruct the orchestrator to load domain-specific references.** In the generic SKILL.md, the orchestrator prompt mentions `core-rules.md` and `language-adaptation.md` but does NOT mention `research-guide.md` as something agents should read. The research-guide is only implicitly passed via the Phase -1 sub-phases. This is fine for the pipeline but means if someone reads only SKILL.md, they won't know research-guide.md exists.

8. **Gap: orchestrator Phase 0+1 references non-existent domain-patterns.md when discovery_needed=false.** If the cache is valid and Phase -1 is skipped, the orchestrator is told "Domain patterns are cached at .audit/domain-patterns.md". The orchestrator's setup (Step 2 of Setup in orchestrator.md) does not explicitly verify this file exists before proceeding to Phase 0. If the file was deleted between SKILL.md's cache check and orchestrator startup, the pipeline would proceed without domain patterns. Low risk but worth a validation step.

## Consistency Check

The generic SKILL.md and tn-nemesis-scan SKILL.md differ in exactly three ways:

1. `name:` frontmatter field (`nemesis-scan` vs `tn-nemesis-scan`)
2. References path in orchestrator prompt (`skills/nemesis-scan/references/` vs `skills/tn-nemesis-scan/references/`)
3. The tn version adds 3 lines of keyword-triggered domain reference loading (protocol-contract-patterns.md and consensus-dag-patterns.md)

**Issue: the `description` frontmatter is identical.** The tn-nemesis-scan description says "Triggers on /nemesis-scan or deep combined audit" -- it should say `/tn-nemesis-scan` to avoid activation conflict. Both skills currently have the same trigger phrases (`/nemesis-scan`, `nemesis scan`, `deep combined audit`). If both skills are installed in the same Claude environment, activation will be ambiguous.

**Issue: the tn-nemesis-scan SKILL.md Activation section is a direct copy.** It still says:
```
- User says `/nemesis-scan` or `nemesis scan` or `deep combined audit`
```
This should say `/tn-nemesis-scan` to differentiate from the generic version.

**Issue: duplicated reference files.** `core-rules.md`, `language-adaptation.md`, and `research-guide.md` are identical copies in both `skills/nemesis-scan/references/` and `skills/tn-nemesis-scan/references/`. This creates a maintenance burden -- edits to shared references must be applied twice. Consider symlinks or a shared references directory.

## Reference Quality

### protocol-contract-patterns.md

**New sections: Region-Aware Shuffle, Slashing System, Dynamic Committee Sizing, Epoch Boundary Atomicity**

**Adversarial sequences -- concrete enough?**
- Region-Aware Shuffle: 4 adversarial sequences, all concrete with specific function names (`setValidatorRegion()`, `setNextCommitteeSize()`), specific state variables, and specific timing windows. Strong.
- Slashing System: 5 adversarial sequences. "Slash amount > validator balance" and "Double slash same validator" are concrete. "Slash during concludeEpoch re-entrancy" references the specific mechanism (`_unstake` ETH transfer). Strong.
- Dynamic Committee Sizing: 4 risk scenarios. "Size change between shuffle and conclude" is concrete. "Committee shrink below quorum" references the quorum formula but doesn't name the specific code that checks (or fails to check) minimum size. **Weakness:** no specific file:line references for where `nextCommitteeSize` is read during shuffle vs. where governance calls `setNextCommitteeSize`.
- Epoch Boundary Atomicity: Describes the merge_transitions mechanism well. However, the audit checklist asks "does the shuffle read stale state from pre-slash" but the mechanism section shows shuffle is pure computation with no state change, which partially answers its own question. **Weakness:** should clarify what state the shuffle reads and from where (pre-slash EVM state or the merged post-slash state).

**Coupled state tables -- all four columns populated?**
- Region-Aware Shuffle table: 3 rows, all 4 columns populated. Row 2 coupling invariant says "Region assignment stable during shuffle" -- could be more specific about what "stable" means (no governance calls between getValidators read and concludeEpoch execution).
- Slashing System table: 3 rows, all 4 columns populated. Complete.
- Dynamic Committee Sizing: **No coupled state table.** This section only has risk scenarios and an audit checklist. Missing the table format used by all other sections.
- Epoch Boundary Atomicity: **No coupled state table.** Only has a mechanism description and audit checklist.

**Audit checklists cover attack surfaces?**
- Region-Aware Shuffle: 5 items covering seed determinism, fallback path, round-robin correctness, unassigned handling, truncation. Missing: what happens when a validator's region is 0 AND they're in the truncated portion -- are they always last?
- Slashing System: 6 items. Covers underflow, future committees, re-entry prevention, retirement check, re-entrancy, duplicates. Thorough.
- Dynamic Committee Sizing: 4 items. Missing: what is the enforced minimum committee size, and where is it checked?
- Epoch Boundary Atomicity: 4 items. Missing: what happens if the shuffle (pure computation) itself panics -- is the partial epoch boundary state rolled back?

### consensus-dag-patterns.md

**New sections: Subscriber Mode Transitions, Batch Builder/Validator, Storage Persistence**

**Adversarial sequences -- concrete enough?**
- Subscriber Mode Transitions: 4 sequences. "CVV -> NVV transition during epoch boundary" is a good scenario but lacks specific function names for the transition logic. The section references `crates/consensus/executor/src/subscriber.rs` at the top but individual sequences don't name the functions that execute transitions. **Weakness:** needs function-level specificity for the transition handlers.
- Batch Builder/Validator: No explicit adversarial sequences section. The concerns are listed as bullet points under "Key concerns" but are not structured as multi-step attack sequences. **Gap:** should include adversarial sequences like "build batch at epoch N-1, deliver at epoch N" or "forge worker identity to inject transactions".
- Storage Persistence: 3 recovery patterns described but not structured as adversarial sequences. **Gap:** should include sequences like "crash during certificate persist -> recover -> stale DAG entry" or "aggressive GC -> state sync request for deleted certificate".

**Coupled state tables -- all four columns populated?**
- Subscriber Mode Transitions: 3 rows, all 4 columns. Row 1 "Output source matches mode" is clear. Row 2 "Subscriber doesn't skip epochs during mode transition" is more of an invariant than a coupling description -- the breaking operation is vague ("Mode change during epoch boundary processing" -- what specific operation?).
- Batch Builder/Validator: 3 rows, all 4 columns populated. Row 3 "Transaction validity / Chain state at batch time" -- the "Breaking Operation" is "State changed between batch creation and execution" which is always true (state always changes). This is too vague to be actionable. Should specify what KIND of state change breaks this (e.g., nonce increment, balance drain, contract upgrade).
- Storage Persistence: 4 rows, all 4 columns populated. Well-structured. Row 3 "Archive index -> Actual certificate data" is specific about the crash-window failure mode.

**Audit checklists cover attack surfaces?**
- Subscriber Mode Transitions: 5 items. Covers drain, epoch skip, watch atomicity, committed round regression, observer memory. Missing: timeout/liveness -- what happens if a mode transition hangs (e.g., NVV -> CVV sync never completes)?
- Batch Builder/Validator: 5 items. Covers epoch boundaries, epoch rejection, deterministic ordering, worker identity verification, size bounds. Missing: what about empty batches (DoS by submitting zero-transaction batches that consume DAG slots)?
- Storage Persistence: 5 items. Covers atomicity, GC/sync interaction, gap handling, durability, index/write race. Thorough.

## Keyword Coverage

**tn-nemesis-scan keyword triggers (from SKILL.md lines 93-94):**

**For protocol-contract-patterns.md:**
Listed keywords: `epoch boundaries, system calls, validator lifecycle, ConsensusRegistry, StakeManager, region, shuffle, geographic, diversity, slash, applySlashes, burn, confiscate, committee size, setNextCommitteeSize`

Missing keywords for new sections:
- **Region-Aware Shuffle section:** `region_aware_shuffle`, `Fisher-Yates`, `round-robin`, `BLS signature hash`, `close_epoch` -- the keyword `shuffle` covers this, but `region_aware_shuffle` as a function name would be more precise.
- **Slashing System section:** `_consensusBurn`, `_exit`, `_retire`, `_unstake`, `Slash[]` -- the keywords `slash, applySlashes, burn, confiscate` cover the main paths. `_consensusBurn` is the key internal function but isn't a keyword. Acceptable since `burn` covers it.
- **Dynamic Committee Sizing section:** covered by `committee size, setNextCommitteeSize`.
- **Epoch Boundary Atomicity section:** `BundleRetention`, `merge_transitions`, `BundleState` -- none of these are keywords. The keyword `epoch boundaries` should trigger this, but if someone is auditing the merge_transitions mechanism specifically, they'd need to target the epoch boundary scope. **Gap:** `merge_transitions` and `BundleRetention` should be keywords.

**For consensus-dag-patterns.md:**
Listed keywords: `consensus state, DAG, certificates, aggregators, state sync, network/peer management, batch, builder, pool, transaction ordering, subscriber, finality, CVV, NVV, observer, storage, persistence, archive, recovery, peer score, Kademlia, reputation`

Missing keywords for new sections:
- **Subscriber Mode Transitions section:** covered by `subscriber, CVV, NVV, observer`.
- **Batch Builder/Validator section:** covered by `batch, builder`.
- **Storage Persistence section:** covered by `storage, persistence, archive, recovery`.
- **Missing from existing sections:** `equivocation` is discussed extensively in the document but not a keyword trigger. `gossipsub` and `authorized_publishers` are discussed but not keywords.

## Actionable Suggestions

1. **Fix tn-nemesis-scan activation conflict.** Change the `description` frontmatter trigger phrase from `/nemesis-scan` to `/tn-nemesis-scan`, and update the Activation section to list `/tn-nemesis-scan` as the primary trigger. Otherwise both skills compete for the same activation phrase.

2. **Add coupled state tables to Dynamic Committee Sizing and Epoch Boundary Atomicity sections** in protocol-contract-patterns.md. Every other section in the file has one. These two sections break the structural pattern and lose the quick-scan value of the table format.

3. **Add explicit adversarial sequences to Batch Builder/Validator and Storage Persistence sections** in consensus-dag-patterns.md. Currently these sections describe concerns and recovery patterns but don't structure them as multi-step attack sequences with specific function calls, which is the format all other sections use.

4. **Add `merge_transitions` and `BundleRetention` to the tn-nemesis-scan keyword triggers** for protocol-contract-patterns.md. These are the specific Rust functions implementing epoch boundary atomicity, and someone auditing that code path would search for them.

5. **Add `equivocation` to the tn-nemesis-scan keyword triggers** for consensus-dag-patterns.md. Equivocation detection is a major subsystem covered in the reference but not surfaced as a keyword.

6. **Sharpen the Batch Builder/Validator coupled state table row 3.** "State changed between batch creation and execution" as a breaking operation is too broad -- every block changes state. Specify the concrete state changes that invalidate batches (nonce increments, balance drainage, epoch transitions, contract upgrades).

7. **Add file:line references to Subscriber Mode Transition adversarial sequences.** The section header references `crates/consensus/executor/src/subscriber.rs` but individual sequences don't name the transition functions. An auditor needs to know which function handles CVV->NVV to trace the attack path.

8. **Eliminate duplicated reference files.** `core-rules.md`, `language-adaptation.md`, and `research-guide.md` are byte-identical across `skills/nemesis-scan/references/` and `skills/tn-nemesis-scan/references/`. Use symlinks from tn-nemesis-scan to nemesis-scan, or extract shared references into a common directory (e.g., `skills/_shared-references/nemesis/`).

9. **Add an orchestrator validation step for domain-patterns.md when discovery is skipped.** The orchestrator should verify `.audit/domain-patterns.md` exists and is non-empty before proceeding to Phase 0, especially when `discovery_needed=false`. A deleted or corrupted cache file would silently degrade all downstream phases.

10. **Clarify in Epoch Boundary Atomicity what state the shuffle reads.** The section shows shuffle as "Pure computation (no state change)" but the shuffle calls `getValidators(Active)` and reads `nextCommitteeSize` -- both of which are reads against EVM state. Clarify whether these reads hit pre-slash or post-slash merged state, since `merge_transitions` has already been called for slashes by this point.

11. **Add a liveness/timeout concern to Subscriber Mode Transitions audit checklist.** The current checklist covers state consistency but not the case where a mode transition stalls (e.g., NVV->CVV sync never completes, leaving the node in a liminal state).

12. **Add empty batch DoS to Batch Builder/Validator audit checklist.** An attacker submitting zero-transaction batches that consume DAG slots could starve legitimate transactions without the checklist flagging this vector.
