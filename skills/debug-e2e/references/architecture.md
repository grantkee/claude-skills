# Telcoin Network Architecture Reference

## System Overview

Telcoin Network is an EVM-compatible blockchain with DAG-based consensus:
- **Consensus Layer (CL)**: Narwhal/Bullshark (derived from Mysten Labs' Sui)
- **Execution Layer (EL)**: EVM on Reth v1.11.3

## Crate Map

### Consensus Layer
| Crate | Path | Purpose |
|-------|------|---------|
| tn-primary | crates/consensus/primary/ | Core consensus: Proposer, Certifier, CertificateFetcher, StateHandler |
| tn-worker | crates/consensus/worker/ | Batch creation, broadcast, QuorumWaiter |
| tn-executor | crates/consensus/executor/ | Bridges CL→EL, forwards consensus output to engine |

### Execution Layer
| Crate | Path | Purpose |
|-------|------|---------|
| engine | crates/engine/ | ExecutorEngine: executes consensus output on EVM state |
| batch-builder | crates/execution/batch-builder/ | Builds batches from tx pool for workers |
| batch-validator | crates/execution/batch-validator/ | Validates batch integrity |

### Infrastructure
| Crate | Path | Purpose |
|-------|------|---------|
| network-libp2p | crates/network-libp2p/ | P2P networking (gossipsub, kademlia, request/response) |
| storage | crates/storage/ | DB layer (ReDB/MDBX/Memory) |
| state-sync | crates/state-sync/ | Sync protocol for non-participating nodes |
| tn-config | crates/config/ | Configuration, genesis, keys |
| tn-types | crates/types/ | Core types (certificates, headers, epochs) |
| tn-node | crates/node/ | Node lifecycle, EpochManager |

### Testing
| Crate | Path | Purpose |
|-------|------|---------|
| e2e-tests | crates/e2e-tests/ | End-to-end process-based tests |
| test-utils | crates/test-utils/ | Unit test helpers |

## Data Flow

```
Transactions → BatchBuilder → Worker (broadcast to quorum) → Primary (include in Header)
→ Certifier (collect 2/3+1 sigs → Certificate) → Bullshark (DAG consensus → CommittedSubDag)
→ Subscriber (fetch batches) → ExecutorEngine (execute on EVM) → SealedBlock
```

## Node Roles
- **CvvActive**: Validator in current committee (runs Primary + Worker + Engine)
- **CvvInactive**: Staked but not in committee this epoch
- **Observer**: Non-validator, syncs execution chain only

## Epoch Lifecycle
```
EpochManager::new() → open consensus DB
  → for each epoch:
    → launch Worker, Primary, Executor
    → wait for epoch boundary (EpochRecord + EpochCertificate with 2/3+1 sigs)
    → teardown & restart with new committee
```

## Key Concurrency Components

### ConsensusBus (consensus/primary/src/consensus_bus.rs)
Central hub connecting all consensus components via channels:
- **Watch channels**: `committed_round_updates`, `primary_round_updates`, `recent_blocks`, `sync_status`, `epoch_record`
- **Broadcast channels**: `consensus_header`, `consensus_output`
- **QueChannel**: Custom mpsc wrapper for epoch-scoped communication with subscriber tracking

### Channel Patterns
- `watch` + `send_replace()` → latest-value state (committed round, sync status)
- `broadcast` → event streams (consensus output); receivers can lag and lose messages
- `QueChannel` → epoch-scoped mpsc with subscriber detection; two modes: skip-if-no-subscriber vs always-queue

## E2E Test Infrastructure

### Test Harness (crates/e2e-tests/src/lib.rs)
- Builds telcoin-network binary once (OnceLock)
- Spawns 4 validators + optional observer as separate processes
- Dynamic RPC ports, isolated IPC paths, separate DBs per node
- ProcessGuard for RAII cleanup (SIGTERM → poll → SIGKILL)
- TestSemaphore limits concurrent tests to 2

### Log Format
```
[TIMESTAMP] [LEVEL] [TARGET]: message [field=value ...]
```
Files: `test_logs/<test_name>/node<instance>-run<run>.log` and `.stderr.log`

### Test Categories
| Test | What It Tests |
|------|--------------|
| epoch_boundary | Epoch transitions, committee shuffling |
| epoch_sync | Epoch sync with node failures |
| restarts | Node restart with 2s delay |
| restarts_delayed | Node restart with 70s delay |
| restarts_lagged_delayed | Restart with lagged validation |
| reconnect | Node reconnection |
| observer | Observer node participation |
| late_join | Late-joining validator |
