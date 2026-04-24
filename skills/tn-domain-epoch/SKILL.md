---
name: tn-domain-epoch
description: |
  Domain expert reference for the epoch lifecycle and node-management layer of telcoin-network.
  Loaded by tn-rust-engineer and tn-domain-reviewer agents when work touches epoch boundaries,
  EpochManager, RunEpochMode, GasAccumulator catchup, governance-driven config updates, or
  anything that reads/writes state at the start or end of an epoch.
  Teaches the canonical-state rules that prevent chain splits at epoch transitions.
  NOT user-invocable. Loaded programmatically by tn-* agents via the Skill tool.
---

# tn-domain-epoch

This skill exists because epoch boundaries are the single most dangerous part of the protocol. Every validator must agree, byte-for-byte, on what state was active at the boundary. A reader that consults the wrong source — canonical tip vs. closing-epoch snapshot, governance-mutable contract vs. pinned epoch record — will produce a different block from its peers, and that's a chain split.

If you are about to modify code that:

- lives under `crates/node/src/manager/**` (EpochManager, `RunEpochMode`, epoch task spawning)
- touches `GasAccumulator`, `WorkerFeeConfig`, base-fee carryover, or per-epoch reward counters
- reads `epoch_state`, `epoch_info`, `EpochState`, or anything derived from `concludeEpoch`
- spawns or shuts down per-epoch tasks (vote collector, primary/worker network handles)
- handles consensus-output replay on startup, mode change, or epoch rollover

…load this skill before writing a single line.

## Why epoch boundaries are different

Within an epoch, parameters are **stable** — committee, worker configs, stake versions, and fee-strategy choices are fixed. Mid-epoch governance calls *may* mutate the underlying contract storage, but those mutations have **no effect** on the running epoch. They take effect only after the closing block applies `concludeEpoch(...)`.

Therefore, two distinct snapshots exist at every boundary:

1. **Closing-epoch final state** — the state root produced by the last block of epoch N. Contains the parameters all validators used during epoch N. This is the canonical reference for anything carried forward (base fees, leader counts, gas totals).
2. **Opening-epoch initial state** — the state root that begins epoch N+1. Contains the new committee and any governance updates applied at close.

Reading the *current* contract storage (canonical tip) instead of one of these two snapshots is the most common cause of validator divergence.

## Invariants

These are hard rules. Violating any of them is a Critical-severity bug.

1. **WorkerConfig at the boundary comes from the closing epoch's final block, never from canonical tip.** Governance can rewrite the `WorkerConfigs` contract mid-epoch, but the values that *applied* during epoch N are pinned in the state at `epoch_info.blockHeight + epoch_info.numBlocks - 1` (or equivalently: the last finalized block whose nonce decodes to epoch == N). Reading from canonical tip leaks future governance into past computation.

2. **Execution state lags consensus.** `reth_env.finalized_header()` may return `None` or an older block than the consensus DB knows about. Never assume a header at a specific number exists during catchup — it may not have been executed yet. If your code falls back to a default when the header is missing, that default must match what every other validator would compute, or you will fork.

3. **Per-epoch state must be reset at `RunEpochMode::NewEpoch`, not at `ModeChange`.** `ModeChange` keeps the epoch alive (e.g., switching observer ↔ active validator). Resetting things like `GasAccumulator` leader counts in `ModeChange` corrupts in-flight epoch totals.

4. **The replay window is `[last_executed_consensus_number + 1, last_committed_consensus_number]`.** Code that catches up from a stored consensus header must not re-execute headers below `last_executed_consensus_number` (double-execution) and must not skip headers above (state divergence). The replay path is the only legitimate way to advance execution past a saved-but-unexecuted consensus output.

5. **Network handles, task managers, and watch channels are epoch-scoped — but the underlying networks are node-scoped.** The `ConsensusNetwork` runs for the lifetime of the node; the *handles* into it (per-epoch `PrimaryNetworkHandle`) get rebuilt every epoch with the new committee. Don't store epoch-scoped handles in node-lifetime structs, and don't tear down node-lifetime networks on epoch transition.

## Pre-write Checklist

Answer each question before writing the change. Write your answers in your scratch context — they don't need to ship in code, but skipping the exercise is how the regression bug got merged.

1. **Which epoch's data am I reading?** Name it: closing epoch N, opening epoch N+1, or "stable mid-epoch". If the answer is "the current value of the contract", you are probably wrong.

2. **What is the canonical source for this value?** Cross-reference `references/canonical-sources.md`. If the value isn't in the table, add it before writing the code.

3. **Is the header I'm reading guaranteed to exist on every node at this point in the pipeline?** During `catchup_accumulator`, `replay_missed_consensus`, or any startup path: probably not. What's the fallback, and would every other validator compute the same fallback?

4. **Does my fallback diverge?** If you write `.unwrap_or(SOME_DEFAULT)` for a value that participates in block production or state transition, the default must be deterministically correct *or* the code path must be unreachable. `MIN_PROTOCOL_BASE_FEE` as a fallback for an EIP-1559 base fee is the canonical example of a forking default.

5. **Will governance ever change this value during the epoch?** If yes, you must read it from a pinned epoch boundary, not canonical tip. `WorkerConfig`, `StakeConfig`, committee membership, and issuance schedule all fall into this bucket.

6. **What state does this leave behind for the next epoch?** `GasAccumulator` totals, base-fee carryover, leader counts — what does the *next* epoch need, and where am I writing it so the next-epoch startup can find it?

## Canonical Sources

Quick lookup for "where do I read X from?". Full version with file pointers in `references/canonical-sources.md`.

| Value needed | Read from | Do NOT read from |
|---|---|---|
| WorkerConfig for epoch N | State at last block of epoch N (`epoch_info.blockHeight + epoch_info.numBlocks - 1`) | Canonical tip; `reth_env.get_worker_fee_configs()` (which reads tip) |
| Committee for epoch N | `EpochRecord` for epoch N in `ConsensusChain` | Live `ConsensusRegistry` storage |
| Base fee carryover (Eip1559) | Last block of closing epoch N | `epoch_state.epoch_info.blockHeight` (start of N+1, may not exist yet) |
| Leader counts for finished rounds | `ConsensusChain::count_leaders` walking consensus DB | `GasAccumulator` (only valid for in-flight rounds) |
| Per-worker gas totals (catchup) | Iterate reth blocks in `[epoch_start_height, finalized_tip]` and call `GasAccumulator::inc_block` | Reading any aggregated counter — there isn't one to read |
| Last executed consensus number | `engine.last_executed_consensus_number()` (engine is the source of truth) | `last_forwarded_consensus_number` (tracks forwarding, not execution) |
| Active vs. observer mode | `consensus_bus.node_mode()` | `builder.tn_config.observer` (only initial config; mode can change) |

## Common Bug Patterns

### Pattern 1: Tip-instead-of-snapshot

The agent reads a governance-mutable value from canonical state when it needs the boundary snapshot. This was the `catchup_accumulator` regression:

```rust
// WRONG — get_worker_fee_configs reads from canonical tip, which reflects
// post-epoch governance updates. Two validators with different sync states
// will see different configs and produce different blocks.
let configs = reth_env.get_worker_fee_configs(num_workers)?;
for (worker_id, config) in configs.iter().enumerate() {
    let base_fee = match config {
        WorkerFeeConfig::Eip1559 { .. } => {
            // WRONG — epoch_info.blockHeight is the START of the new epoch.
            // That block may not be executed yet, falling back to MIN_PROTOCOL_BASE_FEE,
            // which forks against caught-up nodes that read the real value.
            reth_env.header_by_number(epoch_state.epoch_info.blockHeight)?
                .and_then(|h| h.base_fee_per_gas)
                .unwrap_or(MIN_PROTOCOL_BASE_FEE)
        }
        ...
    };
}
```

The fix uses one snapshot for everything: read the closing-epoch's final block once, then derive both the worker configs and the base-fee carryover from that pinned state. The closing-epoch final block is the only state root that all nodes — caught-up or catching up — agree on after consensus has committed the epoch.

### Pattern 2: Forking-default fallback

Any `.unwrap_or(...)` on a value that feeds block production or state transition is a forking risk unless every validator would compute the same fallback under the same conditions. Common offenders: `unwrap_or(MIN_PROTOCOL_BASE_FEE)`, `unwrap_or_default()` on a `U256` fee, `unwrap_or(0)` on a leader count.

The right move is almost never a fallback. It's either: (a) the data is guaranteed to exist at this point in the pipeline (prove it and `expect()` with a clear panic message), or (b) the data may not exist, in which case the surrounding operation should be deferred or skipped, not faked with a default.

### Pattern 3: ModeChange resetting NewEpoch state

Code that resets per-epoch counters runs in the wrong `RunEpochMode` arm:

```rust
// WRONG — ModeChange means we're switching observer/active mid-epoch.
// The epoch is still alive. Resetting GasAccumulator destroys in-flight totals.
match run_epoch_mode {
    RunEpochMode::ModeChange | RunEpochMode::NewEpoch => {
        gas_accumulator.reset();
    }
    _ => {}
}
```

`ModeChange` and `NewEpoch` look symmetric but have opposite meanings for epoch-scoped state. If you're touching the `RunEpochMode` match, list every per-epoch resource and explicitly decide which arm owns its lifecycle.

## Further Reading

- `references/invariants.md` — every invariant with a code-pointer to where it must hold
- `references/bug-patterns.md` — historical bugs caught by this skill, with diffs
- `references/canonical-sources.md` — full value-to-source lookup with file paths and types
