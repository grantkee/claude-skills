# Telcoin-Network Bug Hotspots

Seed reference for Phase 0 (recon) and Phase 1 (mapping). Lists code regions where bugs in the telcoin-network codebase have historically clustered — per category, with file-path hints.

This list is **not exhaustive and not authoritative**. Recon and mapper agents must ground everything they flag in the actual code they read. Treat this file as a starting grep set, not a blessed "known bad" list.

## Layout Assumption

```
/Users/grant/coding/telcoin/telcoin-network/
├── crates/
│   ├── consensus/
│   │   ├── primary/         — header/certificate construction, aggregators, proposer
│   │   ├── worker/          — batch builder, transaction pool, quorum-waiter
│   │   ├── executor/        — subscriber, consensus output, block execution
│   │   └── types/           — shared consensus types
│   ├── engine/              — execution engine boundary
│   ├── network-libp2p/      — gossipsub, request-response, peer scoring
│   ├── node/                — node lifecycle, config, startup
│   ├── state-sync/          — catchup, cert manager, DAG sync
│   ├── storage/             — consensus DB (REDB), archive
│   ├── tn-reth/             — Reth integration, system calls, payload builder
│   ├── tn-types/            — cross-cutting types
│   └── e2e-tests/           — end-to-end test harness (EXCLUDED from audit)
└── tn-contracts/            — Solidity contracts (ConsensusRegistry, StakeManager, Issuance)
```

## 1. Concurrency Hotspots

| Region | Files (pattern) | Smell |
|--------|-----------------|-------|
| Certificate fetcher | `crates/state-sync/src/cert_manager*` | Unbounded channels, `tokio::select!` cancellation paths |
| Certifier | `crates/consensus/primary/src/certifier*` | parking_lot locks across awaits; vote aggregation races |
| Peer-facing handlers | `crates/network-libp2p/src/**/handler*` | Unbounded queues on peer messages; shutdown races |
| Subscriber | `crates/consensus/executor/src/subscriber*` | Mode-transition races (CVV ↔ NVV ↔ observer) |
| Proposer | `crates/consensus/primary/src/proposer*` | Proposal timer cancellation; channel send on shutdown |
| Engine task queue | `crates/engine/src/` | spawn_blocking boundaries for DB work inside async |

Key greps: `parking_lot::`, `unbounded_channel`, `tokio::select!`, `.lock()`, `.await`

## 2. Determinism Hotspots

| Region | Files (pattern) | Smell |
|--------|-----------------|-------|
| Vote aggregators | `crates/consensus/primary/src/aggregators/` | HashMap-backed tally; iterate-to-result |
| DAG traversal | `crates/consensus/*/src/**/dag*` | `BTreeMap<Round, HashMap<AuthorityId, _>>` inner iteration |
| Committee / reputation | `crates/consensus/*/src/**/committee*`, `reputation*` | RNG, iteration order, shuffle |
| Leader election | `crates/consensus/primary/src/**/leader*` | Committee ordering + RNG seeding |
| EVM block construction | `crates/tn-reth/src/**/payload*`, `batch_builder*` | Tx ordering, gas accumulator, timestamp |
| Epoch close | `crates/tn-reth/src/system_calls*`, epoch boundary code | Shuffle, slash ordering, committee sizing |
| Archive | `crates/storage/src/archive/` | **FxHashMap here is SAFE — do NOT flag** |

Key greps: `HashMap`, `HashSet`, `thread_rng`, `SystemTime::now`, `Instant::now`, `par_iter`, `f32`, `f64`

## 3. Consensus / Correctness Hotspots

| Region | Files (pattern) | Smell |
|--------|-----------------|-------|
| Quorum math | aggregators, certifier, batch fetcher | `>=` vs `>`; rounding direction on `total * 2 / 3` |
| Signature verification | certifier, executor, request-response handlers | Fast-path cache that skips re-verification |
| Round/epoch boundary | proposer, subscriber, primary/main loop | Message arrives during boundary tick |
| Equivocation detection | header validation, certifier | Second message from same authority in same round |
| Epoch transition | epoch manager, system calls, `merge_transitions` | Committee change window; state read order vs slash application |
| Certificate validation | cert manager, state-sync | Using wrong epoch's committee to validate |

Key greps: `total * 2`, `stake_total`, `quorum`, `verify_signature`, `epoch.boundary`, `committee`, `merge_transitions`

## 4. State-Atomicity Hotspots

| Region | Files (pattern) | Smell |
|--------|-----------------|-------|
| Gas accumulator catchup | `crates/tn-reth/`, `crates/consensus/executor/` | Coupled: accumulator ↔ block execution result; catchup path vs normal path |
| Epoch manager | epoch manager, `merge_transitions` | Partial apply on panic between slashes/incentives/activate/exit |
| Consensus DB writes | `crates/storage/src/`, REDB table scope | Cross-table writes without a single atomic txn |
| EVM + consensus-DB dual write | `crates/tn-reth/src/system_calls*` + storage | System-call state change alongside consensus-DB record |
| Task manager / node lifecycle | `crates/node/src/` | Mid-restart state; crashed-but-not-flushed |
| Batch builder + pool | `crates/consensus/worker/` | Transaction removal from pool before batch commits |
| Validator activation / exit | `ConsensusRegistry` + Rust bindings in `system_calls.rs` | On-chain state change vs Rust-side view (rust caches stake) |

Key greps: `insert`, `flush`, `sync`, `commit`, `merge_transitions`, `apply_slashes`, `apply_incentives`, `txn.commit`, `durability`

## 5. Panic-Surface Hotspots

| Region | Files (pattern) | Smell |
|--------|-----------------|-------|
| Peer message deserialization | `crates/network-libp2p/src/`, request-response handlers | `.unwrap()` on deserialized bytes |
| RPC handlers | `crates/node/src/rpc*` | Unwrap on user-supplied params |
| DB reads | `crates/storage/src/`, `crates/tn-reth/src/` | Unwrap on potentially-corrupted storage |
| Channel sends | Everywhere | `send().unwrap()` on a channel that can be closed at shutdown |
| Drop impls | `crates/node/`, task manager | Drop that panics kills the process |
| System-call ABIs | `crates/tn-reth/src/system_calls.rs` | Decoding return values from the on-chain registry |
| Slicing / indexing | Header parsing, certificate parsing | `bytes[0..32]` without length check |

Key greps: `.unwrap()`, `.expect(`, `panic!`, `unreachable!`, `todo!`, `unimplemented!`, `debug_assert!`, `bytes[`

## 6. Fork-Risk Hotspots

| Region | Files (pattern) | Smell |
|--------|-----------------|-------|
| System-call ordering | `crates/tn-reth/src/system_calls.rs` | Slash/incentive/activate/exit ordering must be canonical |
| Block constructor | `crates/tn-reth/src/**/payload*`, `batch_builder*` | Base-fee, gas-limit, timestamp derivation — must be deterministic and identical at build and verify |
| Chain-spec reads | wherever `chain_spec` is accessed | Reads at construction time vs verification time |
| System contracts | `tn-contracts/src/` + Rust bindings | Contract logic change must be gated by block height or epoch |
| Payload validation | `crates/engine/`, `crates/tn-reth/` | Same input must produce same state root on every validator |

Key greps: `block.number`, `block_number`, `chain_spec`, `ChainSpec`, `system_calls`, `merge_transitions`

## 7. Error-Propagation Hotspots

| Region | Files (pattern) | Smell |
|--------|-----------------|-------|
| Cross-crate boundaries | Any `pub fn` at a crate boundary | `.map_err(|_| GenericError)` that loses context |
| Async cancellation paths | `tokio::select!` arms, futures boundaries | Dropped error on cancel |
| Match arms over protocol enums | Protocol message handlers | `_ =>` catch-alls that hide new variants |
| Result → Option conversion | Many places | `.ok()` where the caller can't tell absent vs failed |
| Layer-spanning propagation | Engine ↔ consensus, network ↔ consensus | Error type conversions |

Key greps: `.map_err(|_|`, `.ok()`, ` _ => `, `anyhow::anyhow!`, `eyre::eyre!`

## 8. Smart-Contract Hotspots (tn-contracts/)

When the target scope includes `.sol` files:

| Contract | File | Smell |
|----------|------|-------|
| ConsensusRegistry | `tn-contracts/src/ConsensusRegistry.sol` | System-call access control (`msg.sender == systemCaller`); stake tracking; activation/exit state machine |
| StakeManager | `tn-contracts/src/StakeManager.sol` | Reward math; unstake/restake timing; epoch-boundary behavior |
| Issuance | `tn-contracts/src/Issuance.sol` | Tier accounting; total-supply invariant; rounding |

Solidity-specific greps: `onlySystemCall`, `msg.sender`, `require`, `assert`, `transfer`, `call{`, `delegatecall`

## 9. How Phase 0 (recon) Should Use This File

1. For each category, pick 2-4 regions that intersect the target scope.
2. Run the key greps to find the specific line-ranges in scope.
3. Rank targets by how many categories they appear in (a file that hits determinism + state-atomicity + panic-surface is highest priority).
4. Record initial coupling hypotheses (Q0.5) from the state-atomicity hotspots table.

## 10. What NOT To Flag

- **FxHashMap / FxHashSet in `crates/storage/src/archive/`** — deterministic by design.
- **HashMap used as pure lookup** (`.get()`, `.contains()`, `.insert()`) with no iteration into output.
- **`parking_lot` held in a purely-synchronous block with no `.await`** inside — that's the correct use.
- **`SystemTime::now()` used for metrics, log timestamps, or record TTL** — not consensus.
- **`debug_assert!` that is immediately followed by an `if !cond { return; }`** — the `if` is the real guard.
- **Test-only code** — `*test*`, `*bench*`, `test_utils/`, `e2e-tests/`, `#[cfg(test)]`.
- **Deprecated / behind-feature-flag code paths** — unless the feature is on in production.
