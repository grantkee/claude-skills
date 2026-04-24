---
name: tn-domain-worker
description: |
  Domain expert reference for the worker layer of telcoin-network — batch construction,
  transaction pool management, EIP-1559 fee calculation, beneficiary committee enforcement,
  and the worker/primary boundary contract.
  Loaded by tn-rust-engineer and tn-domain-reviewer agents when work touches the worker
  crate, batch-builder, transaction pool, batch fetcher, or quorum-waiter.
  Teaches the rules that keep worker output valid as input to consensus.
  NOT user-invocable. Loaded programmatically by tn-* agents via the Skill tool.
---

# tn-domain-worker

Workers produce the units of work (batches) that consensus orders. A bad batch — wrong epoch tag, wrong base fee, transactions in wrong order, beneficiary not in committee — gets rejected by validating peers and breaks the worker's ability to participate in consensus. Worse, a batch that *passes* validation but should not have produces divergent execution downstream.

If you are about to modify code that:

- lives under `crates/consensus/worker/**`, `crates/batch-builder/**`
- builds, validates, fetches, or signs batches
- manages the transaction pool or computes EIP-1559 base fees
- enforces beneficiary committee membership
- handles worker request/response or batch-fetch coordination

…load this skill before writing a single line.

## Why worker is different

Each batch is a per-epoch unit. Its `epoch` field, its `beneficiary` (block producer), and its base fee must all reflect the worker's currently-active epoch — and the worker's notion of the active epoch must match the network's. Lag or skew between worker and primary on the epoch boundary produces invalid batches.

The other thing about workers: they're the surface area for transaction-pool DoS. Every input is potentially adversarial — bloated transactions, dust spam, replay attempts. Bounded resource usage is a non-negotiable.

## Invariants

1. **`Batch.epoch` must equal the worker's currently-active consensus epoch.** A batch with a stale or future epoch is rejected by peers. The worker must observe epoch transitions via the consensus bus and stop building stale-epoch batches the moment the boundary fires.

2. **Beneficiary must be in the active committee for the batch's epoch.** A batch whose beneficiary is not a committee member at that epoch's boundary cannot legally produce a block. Don't accept batches whose beneficiary fails the committee check, even if other fields are valid.

3. **Base fee follows EIP-1559 from the prior batch in the same epoch.** `new_fee = prev_fee * (1 ± (gas_used - gas_target) / adjustment_factor)`, with the strategy (`Static` vs `Eip1559`) coming from the worker config pinned at the closing block of the *prior* epoch (cross-references `tn-domain-epoch` invariant I-1).

4. **Blob transactions are forbidden in batches.** Blob txs use a separate fee market and storage path that this protocol does not support. Reject at ingest, not at execute.

5. **Batches and the txn pool have hard size bounds.** Pool ingress, batch construction, and peer-batch acceptance must enforce limits — bytes per batch, transactions per batch, pending txs per sender, total pool memory. Unbounded growth here is the canonical worker DoS.

## Pre-write Checklist

1. **What epoch is this batch tagged for?** Source the epoch from a definite signal (consensus bus watch, primary handshake), not from `SystemTime` or local config.

2. **Is the beneficiary in the active committee?** If you're accepting a batch from a peer, validate this before extracting any other field.

3. **Where does the base fee come from?** It should chain from the prior batch in the same epoch using EIP-1559, with the strategy and parameters pinned at the closing block of the prior epoch.

4. **What bounds this resource?** For any allocation (pool entry, batch buffer, peer cache), name the upper bound and how it's enforced.

5. **Is the input adversarial?** Peer batches and txn-pool ingress are. Validate before allocating.

## Canonical Sources

| Value | Source | Avoid |
|---|---|---|
| Active epoch (worker side) | `consensus_bus.current_epoch().borrow()` | Local timestamp; primary RPC at request time |
| Beneficiary check | Membership in committee for `batch.epoch` | Local config; primary's *current* committee if epochs differ |
| Worker fee strategy / params | Closing-epoch's final block state | Live `WorkerConfigs` storage |
| Base fee for first batch of epoch N+1 | Last batch of epoch N's `header.base_fee_per_gas` | Default value if missing — error instead |
| Pool size bound | Configured via `tn_config` (or equivalent) | Implicit "as much as memory allows" |
| Peer-batch validity | All fields validated, beneficiary check passes, epoch matches | "Trust this peer" |

## Common Bug Patterns

### Pattern 1: Stale-epoch batch on transition

Worker builds a batch right as the epoch boundary fires; the batch goes out tagged with the old epoch but is accepted by primary which has rolled to the new epoch. Result: batch fails downstream validation, worker appears to be misbehaving.

Fix: drain the build pipeline at boundary detection, then resume with the new epoch.

### Pattern 2: Beneficiary missing committee check

```rust
// WRONG — accepts batch whose beneficiary may not be in the committee
fn accept_peer_batch(&mut self, batch: Batch) -> Result<()> {
    self.store(batch);
    Ok(())
}
```

Add the membership check against the committee for `batch.epoch` before storage.

### Pattern 3: Unbounded txn pool

```rust
// WRONG — no upper bound; spammer drives node OOM
fn add_tx(&mut self, tx: Tx) {
    self.pool.push(tx);
}
```

Cap pool by total bytes, by sender count, and by per-sender count. Evict by fee.

### Pattern 4: Blob tx leaking through

```rust
// WRONG — blob txs aren't supported but pass basic validation
fn validate_tx(&self, tx: &Tx) -> bool {
    self.basic_check(tx)
}
```

Reject blob-typed txs explicitly at ingest.

### Pattern 5: Base fee from canonical-tip worker config

Same pattern as the `catchup_accumulator` regression but in the worker. If you're computing a base fee at the start of a new epoch, the worker config you use must come from the closing-epoch final block, not the canonical tip.

## Further Reading

- `references/invariants.md`
- `references/bug-patterns.md`
- `references/canonical-sources.md`
