# Known Race Condition Patterns - Telcoin Network

This document catalogs previously fixed race conditions. When debugging a new issue, check whether it matches a known pattern before proposing novel solutions.

## Pattern 1: Synchronous State Update vs Async Processing

**Example**: "Node falls behind" false positive (commit `8d3c2e2e`)

**Mechanism**: Bullshark updates `committed_round` synchronously before the async engine processes outputs. Code that only compared execution round against processed consensus round incorrectly concluded the node was behind.

**Fix**: Include all state sources in the comparison:
```rust
effective_exec_round = exec_round.max(processed_consensus_round).max(committed_round)
```

**Pattern to watch for**: Any comparison between a synchronously-updated value and an asynchronously-updated value that depends on it. The async value will always lag, creating a window where the comparison gives wrong results.

**Where it occurs**: `crates/consensus/primary/src/network/handler.rs`

---

## Pattern 2: Saved-but-not-Forwarded Data Loss

**Example**: Consensus output loss during subscriber shutdown (commit `aa26ae02`)

**Mechanism**: During shutdown, the subscriber saved consensus outputs to the pack file DB but the channel to the execution engine was already closed. The system assumed "saved to DB = delivered" but the engine never received the data.

**Fix**: Track `last_forwarded_consensus_number` separately from DB latest. Add Phase 2 recovery scan during startup that compares forwarded vs saved state.

**Pattern to watch for**: Any path where data is persisted to storage and a downstream consumer is assumed to receive it via a channel. If the channel closes before the consumer reads, the data is "lost" despite being saved.

**Where it occurs**: `crates/node/src/manager/node/epoch.rs`, `crates/consensus/executor/src/subscriber.rs`

---

## Pattern 3: Unbiased Select Priority Inversion

**Example**: Shutdown processed before final consensus output (commit `ad4b91d6`)

**Mechanism**: `tokio::select!` without `biased` randomly chooses between ready futures. When both "data ready" and "shutdown signal" are ready simultaneously, shutdown could win, causing the final data item to be dropped.

**Fix**: Use `tokio::select! { biased; }` with data processing arms before shutdown arms.

**Pattern to watch for**: Any `tokio::select!` that handles both shutdown/cancellation and data processing. Without `biased`, data can be lost when both arms are ready at the same time.

**Where it occurs**: `crates/consensus/executor/src/subscriber.rs`

---

## Pattern 4: Concurrent Per-Entity Operations Without Isolation

**Example**: Vote equivocation race (commit `cb1685a5`)

**Mechanism**: Multiple concurrent vote requests for the same authority processed in parallel. Both checked "no existing vote", both proceeded, creating equivocation.

**Fix**: Per-authority `TokioMutex` in a HashMap. Different authorities can still be voted on in parallel; only same-authority votes are serialized.

**Pattern to watch for**: Any operation that's safe across different entities but must be atomic per entity. A global lock works but kills parallelism; per-entity locks preserve it.

**Where it occurs**: `crates/consensus/primary/src/network/handler.rs`

---

## Pattern 5: Broadcast Channel Silent Drops

**Example**: Tracked in commit `35c4dff9`

**Mechanism**: `tokio::sync::broadcast` channels drop messages when a receiver falls behind (returns `Lagged` error). If the receiver doesn't explicitly handle `Lagged`, messages are silently lost.

**Pattern to watch for**: Any `broadcast::Receiver::recv()` that doesn't handle the `Lagged` variant. In high-throughput paths (consensus output), this can cause permanent divergence between nodes.

---

## Pattern 6: Epoch Transition Channel Windows

**Mechanism**: During epoch transitions, consensus components are torn down and recreated. If a message is sent between teardown of the old epoch's receiver and creation of the new one, it's lost.

**Fix**: The `QueChannel` pattern in `ConsensusBus` — a custom mpsc wrapper that tracks subscriber state via `Arc<AtomicBool>`. Messages sent when no subscriber exists are either dropped (for non-critical paths) or queued (for critical paths like `primary_network_events`).

**Pattern to watch for**: Any channel communication that spans epoch boundaries. Standard tokio channels don't handle the "no receiver yet" case gracefully.

**Where it occurs**: `crates/consensus/primary/src/consensus_bus.rs`

---

## Meta-Pattern: Coordination Complexity

Most race conditions in this codebase trace back to **complex coordination between async components**. The fixes that work best are those that simplify the coordination model rather than adding more synchronization. When proposing solutions:

1. Ask whether the two racing operations need to be separate at all
2. Consider whether a simpler ownership model would eliminate the race
3. Prefer explicit state tracking over channel-delivery assumptions
4. Add timeouts as safety nets, not as the fix itself
