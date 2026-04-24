# Execution-domain invariants — full reference

## I-1: `finalized_header()` is best-effort

**Rule.** Treat `reth_env.finalized_header()` as a hint, never as authoritative for cross-validator computation. It can return `None`, return a stale header, or jump forward at a reorg.

**Where it must hold.** Anywhere `finalized_header()` is called: catchup paths, RPC handlers, restoration logic, observability queries.

**Check.** If the result feeds protocol state (block production, state-root computation, system-call inputs), this is wrong. Replace with an explicit `header_by_number` or `header_by_hash` keyed to the block you actually want.

## I-2: Boundary-derived values come from the closing-epoch final block

**Rule.** Base fee carryover, worker fee configs, stake configs, and any other per-epoch parameter that participates in the next-epoch's block production must be read from the state of the last block of the closing epoch.

**Where it must hold.** `payload_builder.rs` (opening blocks of new epochs), `catchup_accumulator`, `reth_env.get_worker_fee_configs_at(...)` callers.

**Check.** Cross-reference with `tn-domain-epoch` invariant I-1. Both skills enforce this rule from their respective sides — execution is responsible for reading from the right block; epoch is responsible for knowing which block that is.

## I-3: Block production is deterministic given identical input

**Rule.** Two validators with the same `ConsensusOutput`, same parent state, and same protocol parameters must produce byte-identical blocks. Every non-deterministic input is a fork.

**Where it must hold.** `payload_builder.rs`, batch builder's block construction path, system-call application order, transaction sequencing.

**Check.** Audit every input feeding the block: timestamp source, transaction iteration order, address ordering, gas calculations. `HashMap`, `HashSet`, `SystemTime::now()`, RNG, and parallel iteration order are all suspects. Use `BTreeMap`/`BTreeSet`, consensus-supplied timestamps, and explicit sorts.

## I-4: System call ordering at closing block is fixed

**Rule.** The order is: per-block calls → `applyIncentives(rewards)` → `concludeEpoch(newCommittee)`. Slashes apply at the position consensus dictates within this sequence (typically before incentives if any slashes occurred during the closing window).

**Where it must hold.** `crates/tn-reth/src/system_calls.rs`, the closing-block construction in `payload_builder.rs`.

**Check.** When editing closing-block logic, list every `apply_system_call` invocation and verify the order against the protocol spec. Reordering produces a different state root even if all calls fire.

## I-5: Engine state is read-only outside the executor task

**Rule.** Tasks other than the executor may read `recent_blocks`, `last_executed_consensus_number`, and engine status — but cannot mutate engine state. They must also accept that values can advance between reads.

**Where it must hold.** Every consumer of `ConsensusBus::recent_blocks`, every reader of `engine.*` from outside the engine task.

**Check.** Don't compute over engine state across an `.await`. Either snapshot upfront and document the snapshot semantics, or re-read after every await if freshness matters.
