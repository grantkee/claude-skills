---
name: tn-domain-contracts
description: |
  Domain expert reference for the smart-contract integration layer of telcoin-network —
  ConsensusRegistry, StakeManager, and Issuance bindings; system calls (concludeEpoch,
  applyIncentives, applySlashes); validator activation/exit; reward tier accounting.
  Loaded by tn-rust-engineer and tn-domain-reviewer agents when work touches
  crates/tn-reth/src/system_calls.rs, EVM block construction's system-call ordering, or
  any read/write against the on-chain registries from Rust.
  NOT user-invocable. Loaded programmatically by tn-* agents via the Skill tool.
---

# tn-domain-contracts

The on-chain `ConsensusRegistry` and `StakeManager` are the source of truth for committee membership, validator status, stake amounts, and reward tiers. The Rust node interacts with them via system calls fired from inside block execution. Mistakes in this layer are protocol-altering: a wrong committee gets installed, or rewards go to the wrong addresses, or slashes don't apply.

If you are about to modify code that:

- lives in `crates/tn-reth/src/system_calls.rs`, `crates/tn-reth/src/evm/block.rs`
- fires `concludeEpoch`, `applyIncentives`, or `applySlashes` from Rust
- reads `ValidatorInfo`, `EpochInfo`, or `StakeConfig` from contract storage
- decodes contract return values for use in Rust state

…load this skill before writing a single line.

## Why contracts are different

System calls are EVM transactions executed by the node, not by users. They run as part of a block's normal execution but originate from a privileged caller. Two consequences:

1. **Ordering is fixed by protocol, not by Rust ergonomics.** `applyIncentives` runs *before* `concludeEpoch` so rewards credit the closing committee using closing stake versions. Reordering is a state-root divergence.
2. **System-call inputs come from authoritative state, not local config.** The new committee passed to `concludeEpoch` is computed from on-chain stake — not from a local list. Slashes come from consensus evidence, not from local heuristics.

## Invariants

1. **System calls fire exactly once per intended boundary.** `concludeEpoch` fires at the closing block of every epoch; firing it twice or zero times in a single epoch corrupts the registry state.

2. **`applyIncentives` runs before `concludeEpoch` at the closing block.** Incentives credit the closing committee (using their closing stake versions); concludeEpoch then transitions to the new committee.

3. **`applySlashes` runs at its consensus-dictated position.** Typically before incentives if slashes occurred during the closing window; the consensus output specifies the position.

4. **System-call inputs come from authoritative on-chain state.** New committee derives from current stake (after slashes apply); rewards from gas accumulator counters; slashes from consensus evidence.

5. **Contract reads honor block-height pinning.** Reading committee/stake/config for epoch N requires reading at the closing-block height of epoch N (cross-references `tn-domain-epoch` and `tn-domain-execution`).

## Pre-write Checklist

1. **Which system call is this, and at which block does it fire?** Name it. Closing block? Specific intra-epoch position?

2. **What's the input source?** Authoritative on-chain state, gas accumulator snapshot, or consensus evidence — not local config or heuristic.

3. **What's the call ordering relative to other system calls?** If this is at the closing block, list the full sequence: slashes (if any), incentives, conclude. Confirm the order matches the protocol.

4. **What state does this call read or write?** Confirm reads use the right block height; confirm writes affect the next epoch's parameters (not the current one mid-epoch).

5. **Is the return value parsed correctly?** ABI mismatches between Solidity and Rust silently corrupt — pin types and verify with a round-trip test.

## Canonical Sources

| Value | Source | Avoid |
|---|---|---|
| New committee for `concludeEpoch` | Computed from current stake state *after* slashes apply | Local list; pre-slash stake |
| Rewards for `applyIncentives` | `gas_accumulator.rewards_counter()` snapshot at close | Live counter (still mutating) |
| Slash list for `applySlashes` | Consensus output's slash field | Local heuristic (e.g., "this validator missed votes") |
| Validator activation/exit epochs | `ValidatorInfo` in `ConsensusRegistry` | Local timing assumptions |
| Stake version for reward tier | `StakeManager` versioning | Cached value across epochs |
| EpochInfo for past epoch N | Read at closing-block height of N | Live storage (may be from N+1 already) |

## Common Bug Patterns

### Pattern 1: System-call reorder at closing block

`concludeEpoch` runs before `applyIncentives` → incentives credit *new* committee using new stake versions. Wrong recipients, wrong amounts. State-root divergence.

Fix: enforce the order in code, document it next to the call sites.

### Pattern 2: New committee includes inactive validators

The new committee passed to `concludeEpoch` should be derived from active validators *after* slashes have applied. Including inactive or just-slashed validators causes them to attempt participation next epoch and triggers further slashes for inactivity.

### Pattern 3: ABI decode mismatch

```rust
// WRONG — Solidity returns (uint256, address[]); Rust decodes (uint256,) and discards
let (count,): (U256,) = decode(return_data)?;
```

Pin the ABI type alongside the call site; round-trip test in CI.

### Pattern 4: Reading registry from canonical tip for past epoch

To decide who the committee was during epoch N (e.g., to validate a late certificate), don't read live registry — it may show epoch N+1 already. Read at closing-block height of N or use the stored `EpochRecord`.

### Pattern 5: Concluding epoch twice

Double-fire on retry path. Make `concludeEpoch` invocation idempotent against already-applied state, or guard with a "already closed" check.

## Further Reading

- `references/invariants.md`
- `references/bug-patterns.md`
- `references/canonical-sources.md`
