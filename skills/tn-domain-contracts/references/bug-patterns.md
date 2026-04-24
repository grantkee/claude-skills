# Contracts-domain bug patterns

## P-1: System-call reorder at closing block
`concludeEpoch` before `applyIncentives` — incentives credit wrong committee. Enforce order with a typed helper.

## P-2: New committee includes just-slashed validators
Derive new committee from stake state *after* slashes apply, not before.

## P-3: ABI decode mismatch
Solidity returns more fields than Rust decodes. Pin ABI types alongside call sites; round-trip test.

## P-4: Live registry read for historical epoch
Reading `ConsensusRegistry` at canonical tip when you need epoch N's view. Use closing-block-height read or `EpochRecord`.

## P-5: Double `concludeEpoch` on retry
Make idempotent or guard with already-closed check.

## P-6: Slash overruns staked balance
Cap slash at validator's available stake; surface excess as evidence, don't silently truncate.
