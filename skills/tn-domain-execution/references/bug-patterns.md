# Execution-domain bug patterns — historical and instructive

## P-1: Using `finalized_header()` to drive boundary reads

**Bug.** Code uses the finalized header's identity (height, hash) to drive subsequent reads, but the finalized header may be older than the boundary the code is reasoning about. The result: reads at the wrong height with no error.

**Wrong:**
```rust
if let Some(header) = reth_env.finalized_header()? {
    // Assumes `header` is the boundary block — but it's just "some" finalized block
    let configs = reth_env.get_worker_fee_configs_at(header.number, num_workers)?;
}
```

**Right:**
```rust
let epoch_state = reth_env.epoch_state_from_canonical_tip()?;
let closing_final_height = epoch_state.epoch_info.blockHeight
    .saturating_add(epoch_state.epoch_info.numBlocks)
    .saturating_sub(1);

let header = reth_env
    .header_by_number(closing_final_height)?
    .ok_or_else(|| eyre!("closing epoch final block missing at height {closing_final_height}"))?;
let configs = reth_env.get_worker_fee_configs_at(header.number, num_workers)?;
```

**Lesson.** "Some finalized block" and "the boundary block" are different. Always be explicit about the height.

## P-2: HashMap iteration leaking into block production

**Bug.** Transactions sourced from a `HashMap<TxHash, Tx>` are iterated in HashMap order during block construction. Two validators see the same transactions but iterate in different orders → different blocks.

**Wrong:**
```rust
let pending: HashMap<TxHash, Tx> = txn_pool.pending();
for (_, tx) in pending.iter() {
    block_builder.push(tx);
}
```

**Right:**
```rust
let mut pending: Vec<_> = txn_pool.pending().into_iter().collect();
pending.sort_by_key(|(hash, _)| *hash);
for (_, tx) in pending {
    block_builder.push(tx);
}
```

Or better: derive the order from the consensus output that was committed, not from a local pool.

## P-3: System-call reorder at closing block

**Bug.** A refactor groups all system calls into a single helper that calls them in alphabetical order: `apply_incentives`, `apply_slashes`, `conclude_epoch`. The protocol specifies a different order. State root diverges.

**Wrong:**
```rust
fn apply_closing_calls(state: &mut State, ...) {
    apply_incentives(state, rewards);
    apply_slashes(state, slashes);
    conclude_epoch(state, new_committee);
}
```

**Right:** keep the order the protocol dictates and document it explicitly. Slashes apply first (debits stake before reward calculation), then incentives (credits using closing committee's stake), then conclude (transitions to new committee). Don't let alphabetization or refactor convenience reorder them.

## P-4: Reading engine state across await without re-read

**Bug.** RPC handler reads `engine.last_executed_consensus_number()`, awaits a database query, then uses the cached number to derive a response. The engine has advanced during the await; the response describes stale state.

**Wrong:**
```rust
let cursor = engine.last_executed_consensus_number();
let extra = expensive_db_query().await?;
build_response(cursor, extra) // cursor is stale
```

**Right:** re-read the engine cursor after the await, or document explicitly that the response describes "state as of when the request started" (and ensure the rest of the response also uses that snapshot).
