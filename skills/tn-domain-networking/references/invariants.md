# Networking-domain invariants

## I-1: ConsensusNetwork is node-lifetime
Created once in `spawn_node_networks`. Per-epoch handles wrap, do not replace.

## I-2: Topic subscriptions managed at epoch transition
Subscribe new on `NewEpoch`; unsubscribe prior after grace window.

## I-3: Epoch filter precedes downstream dispatch
Inbound message's `epoch` checked against current before forwarding.

## I-4: Codec failures are non-fatal and metered
Drop + peer-score impact + metric. Never panic or unbounded retry.

## I-5: Per-peer / per-protocol bounds
Pending requests, mesh size, fetch buffer, bytes/sec — all explicitly bounded.
