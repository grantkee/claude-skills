# Epoch-domain canonical sources — full lookup

When you need a value at the epoch boundary, look it up here first. The "Source" column gives the only correct read site; the "Why" column explains why other-looking sources diverge.

## Per-epoch parameters (governance-mutable)

| Value | Source | Why this and not other sources |
|---|---|---|
| `WorkerConfig` (per-worker fee strategy) for epoch N | State at last block of epoch N. Compute height as `epoch_info.blockHeight + epoch_info.numBlocks - 1`. | Canonical tip reflects post-close governance updates. The closing-block state is the only one that all validators committed to during epoch N. |
| Committee for epoch N | `EpochRecord` for epoch N in `ConsensusChain` | The on-chain `ConsensusRegistry` may have applied `concludeEpoch(...)` for epoch N+1 by the time you read; the EpochRecord is pinned. |
| `StakeConfig` (reward tier thresholds) for epoch N | State at last block of epoch N | Same reason as WorkerConfig — governance can shift tiers, and the closing block's state is canonical. |
| Issuance schedule active during epoch N | `EpochRecord.stake_version` for epoch N | Lookup table. The version is what the contract stored at boundary; never read live. |

## Per-epoch derived values (carryover)

| Value | Source | Why this and not other sources |
|---|---|---|
| Base fee carryover for opening epoch N+1 (Eip1559) | `header.base_fee_per_gas` of last block of epoch N | This is the fee `adjust_base_fees` wrote at close. The opening block of N+1 hasn't been built yet on a fresh restart — its header may not exist. |
| Per-worker gas totals replay | Iterate reth blocks `[epoch_info.blockHeight, finalized_tip]` and call `GasAccumulator::inc_block(worker_id, gas, limit)` | There is no aggregated counter to read; replay is the source of truth. |
| Leader counts for finished rounds | `ConsensusChain::count_leaders(last_executed_round, gas_accumulator.rewards_counter())` | `GasAccumulator` only tracks in-flight rounds. Finished rounds are recoverable only from consensus DB. |

## Engine / execution state

| Value | Source | Why this and not other sources |
|---|---|---|
| Last executed consensus number | `engine.last_executed_consensus_number()` | This is the engine's authoritative cursor. `last_forwarded_consensus_number` tracks channel-send progress, not execution progress; they can diverge by the channel buffer size. |
| Replay window start | `engine.last_executed_consensus_number() + 1` | Anything earlier double-executes; anything later skips. |
| Replay window end | `consensus_chain.last_committed_consensus_number()` | This is the highest header consensus has agreed on; replaying past it would execute uncommitted output. |
| Finalized header (general) | `reth_env.finalized_header()?` | May be `None` on fresh restart. Treat the `None` case explicitly. |

## Network handles and per-epoch resources

| Value | Source | Why this and not other sources |
|---|---|---|
| Long-running primary network | Created once in `spawn_node_networks`, lives for node lifetime | Restarting per epoch breaks peer connections and partitions the network. |
| Per-epoch primary handle (with committee filter) | `PrimaryNetworkHandle::new_for_epoch(inner_handle, epoch)` rebuilt each epoch | The inner network is shared; the handle wraps it with per-epoch committee context. |
| Active node mode | `consensus_bus.node_mode()` (a watch channel) | `builder.tn_config.observer` is only the initial config; the mode can flip during the node's lifetime. |
| Vote collector lifetime | Spawned per epoch on `node_task_manager.get_spawner()`, scoped to epoch shutdown | Long-living vote collectors leak per-epoch state across boundaries. |

## EpochState fields — what each one means

`EpochState` is returned by `engine.epoch_state_from_canonical_tip()`. Its fields look like they describe the current epoch but actually describe the *next-epoch boundary*:

- `epoch_state.epoch` — the epoch the canonical tip is currently in (this is "live" and may advance)
- `epoch_state.epoch_info.blockHeight` — the block at which the *current* epoch began (start of N)
- `epoch_state.epoch_info.numBlocks` — number of blocks the current epoch has lived
- `epoch_state.epoch_info.epochDuration` — the duration governance set for this epoch

To compute the **last block of the closing epoch** when you're starting epoch N+1:
```
closing_final_height = epoch_info.blockHeight + epoch_info.numBlocks - 1
```

This is the block whose execution applied `concludeEpoch(...)` and pinned all per-epoch parameters. Read everything boundary-related from this height's state, not from `epoch_info.blockHeight` (start of N) or canonical tip (post-N+1 mutations).

## Anti-patterns: sources that look canonical but aren't

These reads compile, run, and look right in tests — but diverge across validators in production.

- `reth_env.get_worker_fee_configs(num_workers)` — reads from canonical tip
- `reth_env.epoch_state_from_canonical_tip()` for *historical* epoch parameters — only valid for the *current* epoch's identity, not its boundary state
- `builder.tn_config.observer` for current mode — initial config only, mode mutates
- `last_forwarded_consensus_number` for execution progress — tracks send-side, not engine-side
- Local timestamp / `SystemTime::now()` for any consensus decision — non-deterministic across nodes
- `HashMap` iteration order over committee or validator lists — non-deterministic; use `BTreeMap` or sort first
