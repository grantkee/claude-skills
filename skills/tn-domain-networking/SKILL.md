---
name: tn-domain-networking
description: |
  Domain expert reference for the libp2p networking layer of telcoin-network — gossipsub
  topics, request-response protocols, peer discovery, epoch-aware filtering, and the
  ConsensusNetwork lifecycle.
  Loaded by tn-rust-engineer and tn-domain-reviewer agents when work touches
  crates/network-libp2p/**, crates/state-sync/**, peer/topic management, or any code that
  publishes/subscribes/requests over the wire.
  Teaches the rules that keep the network from accepting cross-epoch or unauthenticated traffic.
  NOT user-invocable. Loaded programmatically by tn-* agents via the Skill tool.
---

# tn-domain-networking

Networking is the boundary where adversarial input first enters the node. Every byte received from the wire is potentially malicious. This layer's job is to drop, rate-limit, and filter that traffic so downstream layers (consensus, worker) see only well-formed, peer-authenticated, epoch-current messages.

If you are about to modify code that:

- lives under `crates/network-libp2p/**`, `crates/state-sync/**`
- defines or modifies gossipsub topics, request-response protocols, codecs
- handles peer discovery, connection management, peer scoring
- filters or routes messages by epoch
- publishes consensus messages or fetches batches over the network

…load this skill before writing a single line.

## Why networking is different

Two things make this layer special:

1. **Adversarial input.** Anyone with a libp2p connection can send any bytes. Codec errors, oversized messages, protocol-violating sequences must be handled without crashing or spending unbounded resources.
2. **Epoch-coupled lifecycle.** The underlying swarm is node-lifetime, but topics, peer filters, and trust assumptions are per-epoch. Mismatched lifecycle (e.g., subscribing to next-epoch topic before our own boundary fires) leaks future-epoch traffic into current-epoch handling.

## Invariants

1. **`ConsensusNetwork` is created once and lives for the node's lifetime.** Per-epoch handles wrap the inner network with epoch-specific subscriptions and committee filters; the swarm itself does not restart on epoch transition. (Cross-references `tn-domain-epoch` I-5.)

2. **Topic subscriptions are managed at epoch transition.** Subscribe to new-epoch topics on `RunEpochMode::NewEpoch`; unsubscribe from prior-epoch topics after a grace window for late messages.

3. **Inbound messages are filtered by epoch before downstream dispatch.** A header from epoch N+1 received during epoch N must be deferred or dropped, not forwarded to the certifier (which would crash on the epoch mismatch).

4. **Codec failures are non-fatal and metered.** A peer sending malformed bytes triggers a metered drop and possibly a peer-score decrement — never a panic, never an unbounded retry loop.

5. **Per-peer resource limits are enforced.** Bytes/sec, pending requests, batch-fetch concurrency, gossipsub mesh size — all bounded. Unbounded queues here are amplification attacks waiting to happen.

## Pre-write Checklist

1. **Is this code path running on inbound (peer) data?** If yes, treat every byte as adversarial. Validate codec, size, and epoch before allocating downstream resources.

2. **What's the lifecycle of this resource?** Node-lifetime (swarm, listeners), epoch-lifetime (topics, committee filter), or per-message (request-response handler)?

3. **What happens if a peer sends garbage?** Metered drop, peer-score impact, no crash, no unbounded retry. Confirm the path satisfies all four.

4. **What bounds this allocation?** Pending requests per peer, total mesh size, fetch buffer — name the bound and verify enforcement.

5. **Does epoch filtering happen before or after this point?** Before, ideally — downstream handlers should not need to re-check epoch validity.

## Canonical Sources

| Value | Source | Avoid |
|---|---|---|
| Long-running swarm | `ConsensusNetwork` created in `spawn_node_networks`, lives for node lifetime | Per-epoch swarm restart |
| Per-epoch topic name | `LibP2pConfig::*_topic_for(epoch)` (or eq.) | Hardcoded topic strings |
| Active peer set for epoch | Derived from epoch's committee + observers | Live peer list (includes retired validators) |
| Peer score | Per-peer accumulator with metered events | Boolean trust flag |
| Request-response timeout | Configured per-protocol | Default tokio timeout |
| Bound on pending fetches | Per-peer + per-protocol caps | Unbounded `Vec` |

## Common Bug Patterns

### Pattern 1: Per-epoch swarm restart

```rust
// WRONG — restarts swarm per epoch, breaking peer connections
match run_epoch_mode {
    RunEpochMode::NewEpoch => {
        self.network = ConsensusNetwork::new(...)?;
    }
}
```

Keep the swarm alive; rebuild only the per-epoch handle.

### Pattern 2: Forwarding cross-epoch messages

```rust
// WRONG — forwards header from peer in epoch N+1 while we're in epoch N
fn on_header(&mut self, header: Header) {
    self.certifier.process(header);
}
```

Filter `header.epoch` against current epoch first; defer or drop.

### Pattern 3: Unbounded pending fetches

```rust
// WRONG — unbounded; spammer drives node OOM
self.pending.push(fetch_request);
```

Bounded buffer; drop or backpressure when full.

### Pattern 4: Codec error → panic

```rust
// WRONG — peer-controlled bytes; panic = remote DoS
let msg: Header = bincode::deserialize(&bytes).unwrap();
```

Return `Err`, increment a metric, decrement peer score, drop the message.

### Pattern 5: Subscribing to next-epoch topic too early

If we subscribe to epoch N+1's topic before our boundary fires, we receive future-epoch traffic and have to buffer it (or worse, dispatch it to handlers that don't know epoch N+1 yet). Subscribe at the transition, not before.

## Further Reading

- `references/invariants.md`
- `references/bug-patterns.md`
- `references/canonical-sources.md`
