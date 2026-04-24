# Epoch-domain invariants — full reference

Each invariant below restates a rule from SKILL.md, points at the code locations where it must hold, and gives a checking recipe.

## I-1: WorkerConfig at the boundary is pinned to closing epoch's final block

**Rule.** Any code that derives per-epoch parameters (worker configs, base fees, fee strategy) for catchup, replay, or boundary transitions must read from the state root of the *last block of the closing epoch* — not canonical tip, not the opening block of the new epoch.

**Where it must hold.**
- `crates/node/src/manager/node.rs` — `catchup_accumulator`, anywhere `GasAccumulator` is initialized at startup
- `crates/node/src/manager/node/epoch.rs` — `RunEpochMode` transitions
- `crates/tn-reth/src/lib.rs` — anything calling `get_worker_fee_configs`, `epoch_state_from_*`
- `crates/engine/src/payload_builder.rs` — base fee derivation when building the first block of a new epoch

**Why.** Governance mutations to `WorkerConfigs` between blocks are reflected immediately in canonical-tip storage. Validators with different sync timing will read different values. Pinning to the closing-epoch final block makes the read deterministic across all validators because that state root is consensus-committed.

**Check.** Trace the data: where does this value come from? If the chain ends at "current contract storage" or "canonical tip" and the value can change via governance, this is a violation. Replace with a read at `epoch_info.blockHeight + epoch_info.numBlocks - 1` (or equivalent — last block whose nonce decodes to the closing epoch).

## I-2: Execution lags consensus

**Rule.** Code on the catchup/startup/replay path must not assume a header at a specific block number exists. `reth_env.finalized_header()` returning `Some(_)` only tells you *some* header is finalized — not the one you want.

**Where it must hold.**
- `catchup_accumulator` — every `header_by_number` call
- `replay_missed_consensus` — header lookups for replayed consensus outputs
- `try_restore_state` — `last_executed_output_blocks` results may be sparse
- Any RPC handler that responds before the engine has caught up

**Why.** The execution engine processes consensus output asynchronously. On a fresh restart, the consensus DB may know about consensus headers up to N while the EVM has only executed up to M < N. A naive `header_by_number(N)?.unwrap()` on this path crashes; a `.unwrap_or(default)` on this path forks.

**Check.** For every `header_by_number(...)` in startup code, verify: (a) is this header guaranteed to exist at this point in the pipeline? (b) if not, what is the correct response — defer, error, or recompute? Defaulting to a fixed value is almost always wrong.

## I-3: Per-epoch state lifecycle

**Rule.** State scoped to one epoch (leader counts, in-flight gas totals, vote aggregators, per-epoch task handles) must reset on `RunEpochMode::NewEpoch` and only on `RunEpochMode::NewEpoch`. State scoped to the node's lifetime (consensus DB, reth DB, long-running networks) must not reset on any mode transition.

**Where it must hold.**
- `crates/node/src/manager/node/epoch.rs` — the `RunEpochMode` match arms
- `crates/node/src/manager/node.rs` — `consensus_bus.reset_for_epoch()`, task manager scoping
- `GasAccumulator::reset_for_new_epoch` callers

**Why.** `RunEpochMode::ModeChange` keeps the epoch alive (only the validator's role changes — observer ↔ active). Resetting epoch-scoped state during a ModeChange destroys partial progress. Conversely, retaining epoch-scoped state across `NewEpoch` causes leader-count drift and base-fee miscalculation.

**Check.** When editing the `RunEpochMode` match, enumerate every piece of mutable state in scope. For each, write the lifecycle in a comment: which arm initializes it, which arm preserves it, which arm tears it down. If you can't articulate the lifecycle, you don't understand the change yet.

## I-4: Replay window is exact

**Rule.** Catchup that re-executes consensus output must process exactly the range `[last_executed_consensus_number + 1, last_committed_consensus_number]`. Skipping any number causes state divergence; reprocessing any number causes double-execution effects (duplicated gas accounting, duplicated leader counts, duplicated transaction effects on counters that are not idempotent).

**Where it must hold.**
- `replay_missed_consensus` and any helper it calls
- The `to_engine` channel: every `ConsensusOutput` sent must be processed exactly once
- `last_forwarded_consensus_number` tracking — guards against re-forwarding without re-querying

**Why.** Consensus and execution are decoupled by an mpsc channel and a database. A crash can leave the consensus DB ahead of the engine. The replay path is the only legitimate way to catch the engine up. Off-by-one errors here are silent — the chain keeps producing blocks, but their state roots diverge.

**Check.** For any code that iterates consensus headers on startup: explicitly compute the range bounds using `engine.last_executed_consensus_number()` (the source of truth) and `consensus_chain.last_committed_consensus_number()`. Do not derive bounds from any other counter — `last_forwarded_consensus_number` looks similar but tracks a different thing.

## I-5: Network/handle scoping

**Rule.** `ConsensusNetwork` (the libp2p swarm) is created once per node and lives for the node's lifetime. `PrimaryNetworkHandle` and `WorkerNetworkHandle` are *handles* into that swarm and may be cloned per-epoch with epoch-specific committee filters. Tearing down the underlying network on epoch transition kills peer connections and breaks sync.

**Where it must hold.**
- `crates/node/src/manager/node.rs` — `spawn_node_networks` runs once
- `crates/node/src/manager/node/epoch.rs` — handles get rebuilt per epoch but the network task isn't restarted
- `crates/network-libp2p/src/consensus.rs` — peer subscriptions are per-epoch but the swarm is persistent

**Why.** libp2p peer establishment is expensive; restarting it per epoch causes consensus pauses while peers reconnect. More dangerously, retiring validators from epoch N may still be needed to gossip late certificates or sync help to laggers — losing the connection prematurely partitions the network.

**Check.** Anything that looks like "create a new ConsensusNetwork inside the per-epoch loop" is wrong. Per-epoch components should call `network_handle.subscribe(epoch_topic)` and `network_handle.unsubscribe(prev_epoch_topic)` rather than rebuilding the network.
