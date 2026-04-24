---
name: tn-domain-execution
description: |
  Domain expert reference for the execution layer of telcoin-network — Reth integration,
  EVM block production, payload building, and the executor/engine boundary contract.
  Loaded by tn-rust-engineer and tn-domain-reviewer agents when work touches reth_env,
  payload builder, batch builder's block-shaping logic, base fee derivation, or anything
  that reads or writes EVM state.
  Teaches the rules that prevent execution divergence across validators.
  NOT user-invocable. Loaded programmatically by tn-* agents via the Skill tool.
---

# tn-domain-execution

The execution layer in telcoin-network is a Reth-backed EVM that consumes `ConsensusOutput` and produces blocks. It runs *behind* consensus — the consensus DB always knows about more headers than the engine has executed. That asynchrony is the single most important fact about this layer; almost every divergence bug in execution is a misuse of state at the consensus/execution boundary.

If you are about to modify code that:

- lives under `crates/engine/**`, `crates/tn-reth/**`, `crates/batch-builder/**`
- calls `reth_env.*` for headers, state, finality, or worker fee configs
- builds, validates, or sequences EVM blocks (`payload_builder.rs`, block executor)
- derives base fees, applies system calls, or computes state roots
- handles canonical reorgs, state restoration, or `try_restore_state`

…load this skill before writing a single line.

## Why execution is different

The engine is a *follower* of consensus. Consensus commits a `ConsensusOutput`, persists it to the consensus DB, and forwards it to the engine via mpsc. The engine then builds and executes the block. Crash recovery, mode changes, and slow execution can all leave the engine arbitrarily behind consensus.

That means three things must always be true of every read in this layer:

1. **Reads of "the canonical tip" reflect engine progress, not consensus progress.** The chain you see may be many consensus outputs behind.
2. **Reads of "the finalized header" can return `None` on fresh restart**, or return a header much older than the latest committed consensus.
3. **Reads of contract storage at canonical tip** reflect any system-call mutations the engine has executed — but not ones from outputs the engine hasn't processed yet.

Code that mixes "look at canonical tip" with "look at consensus DB" without understanding which one is ahead is the breeding ground for forks.

## Invariants

1. **`reth_env.finalized_header()` is best-effort, not authoritative.** It may return `None`, return a stale header, or skip ahead at a reorg. Never use it as the sole source for cross-validator state. If you need a specific block's state, fetch by number or hash and explicitly handle the missing case.

2. **The closing-epoch final block is the canonical snapshot for boundary-derived values.** Base fee carryover, worker fee configs, and any system-call output for epoch N must be read from the state at the last block of epoch N — not canonical tip, not the opening block of N+1. (Cross-references `tn-domain-epoch` invariant I-1; both skills enforce this from their respective sides.)

3. **Block production is deterministic across all validators given identical input.** That requires: identical transaction order, identical timestamp, identical base fee, identical beneficiary, identical system-call results. Any non-deterministic source (HashMap iteration over a transaction set, `SystemTime::now()` for the block timestamp, a random gas-limit perturbation) is a fork.

4. **`payload_builder` must apply system calls in a fixed order at fixed boundaries.** `applyIncentives` runs before `concludeEpoch` in the closing block; `applySlashes` runs at the position consensus dictates. The order is part of the protocol — reordering is a state-root divergence even if the same calls all fire.

5. **Engine state is read-only outside the executor task.** Any other task that reads engine state via `recent_blocks` watch channels, the consensus bus, or `last_executed_consensus_number` must accept that the value can advance between consecutive reads. Don't compute over engine state across `await` points without re-reading.

## Pre-write Checklist

1. **Where is the engine right now?** Specifically: which is the highest consensus number it has executed? Are you reading state from after that point? If yes, what guarantees that state exists?

2. **What's the determinism story?** List every input that feeds the value you're computing. For each, name the source and confirm all validators see the same value. If a `HashMap`, `SystemTime`, RNG, or thread-ordering dependency appears, stop and switch sources.

3. **Does this run in the executor task or outside?** If outside, you cannot mutate engine state. You can only consume it via the channels and watches the engine exposes.

4. **Does this read contract storage?** If yes: at what block? "Canonical tip" is rarely the right answer. The closing-epoch final block, an explicit historical block, or a system-call result snapshot are the canonical alternatives.

5. **Does this fall back when state is missing?** If yes: would all validators compute the same fallback under identical conditions? If not, this is a forking default. Replace with an explicit error or defer the operation.

6. **Does this respect the `applyIncentives` → `concludeEpoch` ordering at the closing block?** If you're touching boundary block construction, list every system call you fire and verify the order matches the protocol.

## Canonical Sources

| Value | Read from | Do NOT read from |
|---|---|---|
| EVM state at block N | `reth_env.state_at_block(N)` (after verifying N exists) | Implicit "canonical tip" reads when N is what you actually want |
| Worker fee configs at boundary | `reth_env.get_worker_fee_configs_at(closing_final_height, ...)` | `reth_env.get_worker_fee_configs(...)` (reads tip) |
| Base fee for opening epoch N+1 | `header.base_fee_per_gas` of last block of epoch N | A computed/derived fallback if the header is missing — defer instead |
| Last executed consensus number | `engine.last_executed_consensus_number()` | Any cached counter elsewhere; the engine is the source of truth |
| Block timestamp | `consensus_output.committed_at` (consensus-supplied) | `SystemTime::now()` in any code path |
| Transaction order in a block | The order specified by `ConsensusOutput.batches` | Any iteration order over a `HashMap`, `HashSet`, or unordered collection |
| Beneficiary (block producer) | Resolved from the leader of the consensus round, validated against committee at boundary | Any address from local config or RPC input |

## Common Bug Patterns

### Pattern 1: Using `finalized_header()` where a specific block is needed

```rust
// WRONG — finalized_header returns "some" finalized block, not the boundary block
if let Some(block) = reth_env.finalized_header()? {
    let configs = reth_env.get_worker_fee_configs(num_workers)?;
    // configs are read from canonical tip, not from `block`
}
```

The fix: explicitly compute the height you want, fetch by number, and read everything from that pinned point. `finalized_header()` is appropriate only when "any recent finalized block" is genuinely what you need (e.g., for a non-deterministic display value), which is rare in protocol code.

### Pattern 2: Non-deterministic block input

```rust
// WRONG — HashMap iteration order is non-deterministic across runs
let txs: HashMap<TxHash, Tx> = ...;
for (_, tx) in txs.iter() {
    block.add_tx(tx);
}
```

The fix: iterate in a defined order (sort by hash, by sender+nonce, or by the order consensus supplied). Any time you see `HashMap`/`HashSet` near block construction, treat it as a divergence flag.

### Pattern 3: Reordering system calls at the closing block

```rust
// WRONG — concludeEpoch must run AFTER applyIncentives, not before
fn build_closing_block(...) {
    apply_system_call(SystemCall::ConcludeEpoch(new_committee));
    apply_system_call(SystemCall::ApplyIncentives(rewards));
}
```

The fix: incentives credit accounts using the *closing* committee's stake; `concludeEpoch` then transitions to the *new* committee. Reversing the order pays incentives to the new committee using the new stake versions, which is wrong and produces a different state root from the rest of the network.

### Pattern 4: Crossing await points without re-reading engine state

```rust
// WRONG — engine state may have advanced during `slow_op().await`
let last = engine.last_executed_consensus_number();
let response = slow_op().await?;
do_work_assuming(last); // `last` may now be stale
```

The fix: re-read engine state after every await if its freshness matters, or take a snapshot upfront and document that the snapshot is what the operation operates on (not "current" state).

## Further Reading

- `references/invariants.md` — every invariant with code-pointer to where it must hold
- `references/bug-patterns.md` — historical bugs caught by this skill
- `references/canonical-sources.md` — full value-to-source lookup with file paths
