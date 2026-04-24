# Epoch-domain bug patterns — historical and instructive

A growing catalog of real bugs and near-misses caught at the epoch boundary. Each entry includes the original (broken) code, the root cause, and the fix.

When you find a new bug in this domain, add it here so the next reviewer catches the same shape.

---

## P-1: `catchup_accumulator` reads worker configs from canonical tip

**Bug.** During mid-epoch restart, the accumulator's per-worker base fee is read from `reth_env.get_worker_fee_configs()`, which queries the canonical tip's storage. Governance updates to `WorkerConfigs` between the closing block and restart leak into the catchup, producing a different base fee than the rest of the network used.

**Compounding bug.** The Eip1559 path falls back to `MIN_PROTOCOL_BASE_FEE` if the header at `epoch_state.epoch_info.blockHeight` doesn't exist yet (execution lags consensus). Two validators starting at different times will see different base fees → fork.

**Wrong:**
```rust
let configs = reth_env.get_worker_fee_configs(num_workers)?;
for (worker_id, config) in configs.iter().enumerate() {
    let base_fee = match config {
        WorkerFeeConfig::Static { fee } => *fee,
        WorkerFeeConfig::Eip1559 { .. } => {
            reth_env
                .header_by_number(epoch_state.epoch_info.blockHeight)?
                .and_then(|h| h.base_fee_per_gas)
                .unwrap_or(MIN_PROTOCOL_BASE_FEE)
        }
    };
    gas_accumulator.base_fee(worker_id as u16).set_base_fee(base_fee);
}
```

**Right.** Read both the worker configs *and* the carryover base fee from the same pinned snapshot — the state at the closing epoch's final block. That state root is consensus-committed, so all validators agree on its contents:

```rust
// derive the closing epoch's final block height from the canonical-tip epoch_state
let closing_final_height = epoch_state.epoch_info.blockHeight
    .saturating_add(epoch_state.epoch_info.numBlocks)
    .saturating_sub(1);

// read worker configs from the closing epoch's final block state, NOT canonical tip
let configs = reth_env
    .get_worker_fee_configs_at(closing_final_height, gas_accumulator.num_workers())?;

for (worker_id, config) in configs.iter().enumerate() {
    let base_fee = match config {
        WorkerFeeConfig::Static { fee } => *fee,
        WorkerFeeConfig::Eip1559 { .. } => {
            // closing-epoch final block is guaranteed to exist post-finality —
            // it's the block whose execution committed the epoch close
            reth_env
                .header_by_number(closing_final_height)?
                .and_then(|h| h.base_fee_per_gas)
                .ok_or_else(|| eyre!("closing epoch final block missing base fee"))?
        }
    };
    gas_accumulator.base_fee(worker_id as u16).set_base_fee(base_fee);
}
```

**Lesson.** Always pin the snapshot first, then read every related parameter from that snapshot. Using two different sources for related values (configs from tip, base fee from a different block) is a divergence trap.

---

## P-2: `RunEpochMode::ModeChange` accidentally resets epoch-scoped state

**Bug.** A refactor that grouped `ModeChange` and `NewEpoch` arms together — they both spawn fresh per-epoch tasks, so it looked like they should reset the same state. But `ModeChange` keeps the epoch alive; resetting `GasAccumulator` mid-epoch drops in-flight leader counts and gas totals, causing the closing-block computation to use wrong values.

**Wrong:**
```rust
match run_epoch_mode {
    RunEpochMode::Initial => initialize_first_epoch(),
    RunEpochMode::ModeChange | RunEpochMode::NewEpoch => {
        gas_accumulator.reset();
        consensus_bus.reset_for_epoch();
        spawn_epoch_tasks();
    }
}
```

**Right:**
```rust
match run_epoch_mode {
    RunEpochMode::Initial => initialize_first_epoch(),
    RunEpochMode::ModeChange => {
        // observer ↔ active flip mid-epoch — keep gas accumulator and bus state
        spawn_epoch_tasks();
    }
    RunEpochMode::NewEpoch => {
        gas_accumulator.reset();
        consensus_bus.reset_for_epoch();
        spawn_epoch_tasks();
    }
}
```

**Lesson.** When two enum arms look symmetric, list every piece of state they touch and ask whether the lifecycle really matches. `ModeChange` and `NewEpoch` are a notorious false-equivalence in this codebase.

---

## P-3: Forking-default fallback on missing finalized header

**Bug.** Code on the catchup path uses `.unwrap_or(SOME_DEFAULT)` for a value that participates in block production. If the default is hit on one validator and not another, blocks diverge.

**Wrong:**
```rust
let base_fee = reth_env
    .header_by_number(height)?
    .and_then(|h| h.base_fee_per_gas)
    .unwrap_or(MIN_PROTOCOL_BASE_FEE); // forks if other validators have the header
```

**Right.** If the header is *guaranteed* to exist by an upstream invariant, prove it and panic with a clear message; the panic is preferable to a silent fork:

```rust
let header = reth_env
    .header_by_number(height)?
    .ok_or_else(|| eyre!("invariant violation: header at {height} should exist post-finality"))?;
let base_fee = header.base_fee_per_gas
    .ok_or_else(|| eyre!("invariant violation: post-Shanghai header missing base fee"))?;
```

If the header may legitimately be missing, the correct response is to defer the operation, not to fake a value.

**Lesson.** `.unwrap_or` on consensus-critical values is almost never the answer. The two correct responses are: prove existence and crash on violation, or defer the operation until existence is established.

---

## P-4: Storing epoch-scoped handle in node-lifetime struct

**Bug.** A new feature stored a `PrimaryNetworkHandle` keyed to epoch N inside a node-lifetime struct. When epoch N+1 began, the handle still pointed at the epoch-N committee filter, causing the feature to publish messages with the wrong epoch tag.

**Wrong:**
```rust
struct EpochManager {
    primary_handle: Option<PrimaryNetworkHandle>, // captured at startup, never refreshed
    ...
}
```

**Right.** Either store the long-lived inner handle (and re-derive the epoch-scoped wrapper each epoch), or pass the handle through the per-epoch task spawner so it gets rebuilt:

```rust
struct EpochManager {
    primary_inner: Option<NetworkHandle<...>>, // long-lived — stays for node lifetime
    ...
}

// per-epoch:
let primary_handle = PrimaryNetworkHandle::new_for_epoch(self.primary_inner.clone(), epoch);
```

**Lesson.** Anything with "epoch" in its name or behavior is per-epoch by default. Storing it in a longer-lived scope without explicit refresh is the bug.
