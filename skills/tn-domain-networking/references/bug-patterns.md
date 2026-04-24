# Networking-domain bug patterns

## P-1: Per-epoch swarm restart
Breaks peer connections at boundary. Keep swarm alive; rebuild handle only.

## P-2: Cross-epoch message forwarded
Filter by `msg.epoch` before dispatch.

## P-3: Unbounded pending fetches
Cap with backpressure; drop or rate-limit.

## P-4: Codec error → panic
Adversarial input. Return Err, metric, peer-score, drop.

## P-5: Subscribe next-epoch topic too early
Subscribe at transition, not before.

## P-6: Peer score never decays
Slashable misbehavior accumulates indefinitely; honest peers eventually penalized for transient errors. Add decay.

## P-7: Trusting peer's claimed epoch
Use peer's epoch for filtering only; trust must come from signature against the message's epoch's committee.
