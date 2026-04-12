# Consensus DAG Patterns

Reference file for the Nemesis auditor. Load when auditing DAG-based BFT consensus code, certificate handling, vote aggregation, state synchronization, or peer/network management.

## DAG-BFT Coupled State Pairs

These pairs within the consensus layer must stay synchronized. A mutation to one without updating its counterpart causes state corruption or consensus divergence.

| State A | State B (coupled) | Coupling Invariant | Breaking Operation |
|---------|-------------------|-------------------|-------------------|
| `ConsensusState.last_round.committed_round` | `ConsensusState.last_committed` HashMap | `committed_round == max(last_committed.values())` | Commit updates one but not the other |
| `ConsensusState.last_round.gc_round` | `ConsensusState.dag` BTreeMap | DAG contains no entries for rounds <= gc_round | GC deletes from dag but doesn't update gc_round, or vice versa |
| `ConsensusState.dag` entries | Certificate store (persistent) | DAG is a subset of persisted certificates | Certificate persisted but not inserted into DAG, or DAG entry without persistence |
| `authorized_publishers` HashMap | Current committee | Publishers == committee members for consensus topics | Committee rotates but authorized_publishers not updated |
| `PeerManager.known_peers` (BLS → NetworkInfo) | `PeerManager.known_peerids` (PeerId → BLS) | Bidirectional: every key in known_peers has a reverse entry in known_peerids | Add/remove from one map but not the other |
| `CertificateManager.pending` | Missing parent requests | Every pending cert has an outstanding parent fetch | Parent fetch completes but pending cert not re-evaluated |
| `VotesAggregator.weight` | `VotesAggregator.verified_votes` + `authorities_seen` | weight == sum of voting power for authorities in authorities_seen | Vote added to verified_votes but weight not incremented |
| `CertificatesAggregatorManager.aggregators` | GC round | No aggregator exists for rounds <= gc_round | GC advances but old aggregators not cleaned up |
| `ConsensusBus` watch channels | Actual consensus state | Watch values reflect latest committed state | State updated but watch sender not notified |
| `RequestHandler.auth_last_vote` | Current epoch | Vote map is scoped to current epoch only | Epoch changes but stale votes from previous epoch remain |

## Certificate and Vote Aggregation Invariants

### Quorum Threshold
The quorum threshold is `2f + 1` where `f = (committee_size - 1) / 3`. This is the minimum voting power needed to form a certificate from votes, or to have enough parent certificates to propose a new header.

**Audit checklist:**
- [ ] Quorum is computed from `committee.quorum_threshold()` — never hardcoded
- [ ] Weight accumulation uses the authority's actual voting power from the committee, not a count of votes
- [ ] Quorum check is `>=` threshold (not `>`)
- [ ] Committee changes between epochs don't leave stale quorum thresholds

### Vote Aggregation (`VotesAggregator`)
```
For each incoming vote:
  1. Check authority is in current committee
  2. Check authorities_seen does NOT contain this authority (equivocation detection)
  3. Add to authorities_seen
  4. Add voting power to weight
  5. Add (authority, signature) to verified_votes
  6. If weight >= quorum_threshold → return aggregated certificate
```

**Equivocation detection:** Uses `HashSet<AuthorityIdentifier>` (`authorities_seen`). A validator voting twice for the same round is detected by set membership check.

**Audit focus:**
- [ ] `authorities_seen.insert()` is checked BEFORE adding weight (prevents double-counting)
- [ ] Equivocation is detected but does not crash — the duplicate vote is simply ignored
- [ ] The aggregator is scoped per (epoch, round, header) — votes for different headers don't mix
- [ ] Aggregator state is cleaned up after certificate creation (no unbounded growth)

### Certificate Aggregation (`CertificatesAggregator`)
```
For each incoming certificate for round R:
  1. Check authority is in committee
  2. Check authorities_seen does NOT contain this authority
  3. Add to authorities_seen, accumulate weight
  4. Add certificate to certificates vec
  5. If weight >= quorum_threshold → return certificates as parents
```

**Managed by `CertificatesAggregatorManager`:**
- Maintains `BTreeMap<Round, Box<CertificatesAggregator>>` — one aggregator per round
- `garbage_collect(round)` removes all aggregators for rounds <= given round
- New rounds lazily create aggregators on first certificate arrival

**Audit focus:**
- [ ] Garbage collection doesn't delete an aggregator that hasn't yet reached quorum
- [ ] Late-arriving certificates for collected rounds are silently dropped (not panic)
- [ ] The BTreeMap grows bounded — old entries are cleaned up as rounds advance

## Determinism Risks

Non-deterministic operations in consensus paths cause validators to diverge. Every validator must reach the same decision given the same inputs.

### HashMap/HashSet Iteration
- `ConsensusState.last_committed: HashMap<AuthorityIdentifier, Round>` — if iterated to compute committed_round, iteration order varies across runs
- `authorized_publishers: HashMap<String, Option<HashSet<BlsPublicKey>>>` — iteration for authorization checks is order-independent (set membership), but logging iteration order could mask bugs
- `RequestHandler.consensus_certs: HashMap<BlockHash, u32>` — tracking quorum on consensus headers

**Rule:** HashMap iteration order must NEVER influence consensus decisions. If results are collected from HashMap iteration, they must be sorted or reduced to an order-independent value.

### Timestamp Usage
- `TimestampSec` in consensus header digests — used for leader election timing and epoch boundary detection
- `Instant::now()` for local timeouts — acceptable for local decisions but must not influence consensus output
- Epoch boundary: `epoch_start + epochDuration` — both sides must use the same clock source

**Rule:** Only deterministic timestamps (from consensus headers) may influence consensus state transitions. Wall-clock time may only gate local retry/timeout behavior.

### Floating Point
- Reward weight calculation uses integer arithmetic (safe)
- Reputation scores in `LeaderSchedule` — verify no floating point in score computation

**Rule:** No floating point in any path that affects consensus output or state transitions.

## Garbage Collection Window Exploitation

The consensus DAG uses garbage collection to bound memory. The GC window creates attack surfaces.

```
gc_round = committed_round - gc_depth
DAG entries with round <= gc_round are eligible for deletion
```

**Attack patterns:**
- **Parent deletion race:** A certificate at round R references parents at round R-1. If GC advances past R-1 before the certificate is fully processed, parent lookup fails
- **Pending certificate starvation:** Certificate arrives with parents below GC round. It can never be accepted because parents are gone. Does it stay in pending forever (memory leak)?
- **GC depth manipulation:** If gc_depth is configurable or derived from committee size, a small committee could shrink the GC window, causing premature parent deletion
- **Recovery after crash:** `construct_dag_from_cert_store()` rebuilds DAG from persistent storage. If GC deleted certificates from storage too, recovery has gaps

**Audit checklist:**
- [ ] Pending certificates with parents below GC round are explicitly dropped, not left indefinitely
- [ ] GC deletes from DAG and persistent storage atomically (or in correct order)
- [ ] `gc_depth` is a protocol constant, not derived from mutable state
- [ ] Recovery path handles missing certificates gracefully (doesn't panic on gaps)

## State Sync Attack Patterns

State synchronization allows nodes to catch up by fetching certificates from peers. This is a trust boundary.

### Certificate Fetching
- `StateSynchronizer::process_peer_certificate()` — validates peer-provided certificates
- `process_fetched_certificates_in_parallel()` — batch validation of fetched certs
- `identify_unkown_parents()` — finds missing parents to request from peers

**Attack patterns:**
- **Malicious certificate injection:** Peer sends a valid-looking certificate with forged signatures. Signature verification must be complete (all signers checked against committee)
- **Out-of-order delivery:** Peer sends child certificates before parents. The pending manager must handle this without deadlock or unbounded buffering
- **Stale committee injection:** Peer sends certificates from a previous epoch with an old committee. Epoch scoping must reject these
- **Flood attack on pending queue:** Send many certificates with missing parents to fill the pending queue. Must have bounded pending storage
- **Selective withholding:** Peer provides some parents but not others, keeping certificates permanently pending. Timeout or alternative peer fallback needed

### Epoch Record Validation
- Epoch transitions require reading `EpochInfo` from Solidity state
- `get_committee_with_epoch_start_info()` fetches committee from canonical tip

**Attack patterns:**
- **Forged epoch info:** If epoch info is fetched from an untrusted source (not canonical state), committee can be spoofed
- **Epoch boundary timing attack:** Manipulate block timestamps to trigger premature or delayed epoch transitions
- **Committee mismatch:** Rust reads committee at block N, Solidity state changed at block N+1. Race between read and state update

## Network Security Patterns

### Gossipsub Authorization
The `authorized_publishers` HashMap maps topic names to optional sets of allowed BLS public keys.

```
authorized_publishers: HashMap<String, Option<HashSet<BlsPublicKey>>>
  None        → topic is open (anyone can publish)
  Some(set)   → only keys in set can publish to this topic
```

**Audit checklist:**
- [ ] `update_authorized_publishers()` is called on every committee change (not just epoch start)
- [ ] Old committee members are removed, not just new ones added
- [ ] The gap between committee change and publisher update doesn't allow unauthorized messages
- [ ] Topics without authorization (None) are not consensus-critical

### Peer Management
`PeerManager` maintains bidirectional maps for peer identity:

```
known_peers:   BlsPublicKey → NetworkInfo  (committee members + bootstrap)
known_peerids: PeerId       → BlsPublicKey (reverse lookup)
```

**Audit checklist:**
- [ ] Add operations update both maps atomically
- [ ] Remove operations update both maps atomically
- [ ] `temporarily_banned` peers are checked before accepting connections
- [ ] `discovery_peers` (from Kademlia DHT) are not automatically trusted as committee members
- [ ] Peer reputation changes don't create inconsistency between the two maps

### Equivocation Detection in Network Handler
`RequestHandler.auth_last_vote` tracks the last vote per authority to detect equivocation:

```
auth_last_vote: Arc<AuthEquivocationMap>
  Maps: AuthorityIdentifier → (Epoch, Round, HeaderDigest, VoteResponse)
```

**Audit checklist:**
- [ ] Equivocation map is cleared on epoch transition (old votes are irrelevant)
- [ ] A validator voting for two different headers in the same round is detected and rejected
- [ ] The check happens before the vote is forwarded to the aggregator (not after)
- [ ] The map doesn't grow unbounded across rounds within an epoch

## Bullshark Protocol Patterns

Bullshark is the DAG-based BFT consensus protocol. It commits leaders at even rounds.

**Key state:**
- `Bullshark.leader_schedule` — determines leader for each even round
- `Bullshark.max_inserted_certificate_round` — highest round seen
- `ConsensusState.dag` — the DAG of certificates

**Audit focus:**
- [ ] Leader election is deterministic given the same DAG state
- [ ] `commit_leader()` commits the correct sub-DAG (all ancestors of the leader certificate)
- [ ] Reputation scoring doesn't introduce non-determinism (no HashMap iteration for scoring)
- [ ] `num_sub_dags_per_schedule` resets happen at the same point for all validators
- [ ] A committed sub-DAG is never re-committed (idempotency)

## Consensus Bus Watch Channel Patterns

The `ConsensusBus` uses tokio `watch` channels to broadcast state updates. Watch channels have specific semantics that affect correctness.

**Key channels:**
- `committed_round_updates: watch::Sender<Round>` — latest committed round
- `primary_round_updates: watch::Sender<Round>` — latest primary round
- `node_mode: watch::Sender<NodeMode>` — CVV active/inactive/observer
- `last_consensus_header: watch::Sender<Option<ConsensusHeader>>`

**Watch channel semantics:**
- Only the LATEST value is retained — intermediate values are lost
- Receivers see the latest value when they next poll, not every value
- This is correct for monotonically increasing values (rounds) but dangerous for non-monotonic state

**Audit checklist:**
- [ ] All watch channel values are monotonically increasing or last-write-wins safe
- [ ] No consumer depends on seeing every intermediate value (use `QueChannel` for that)
- [ ] `committed_round_updates` is sent AFTER the commit is fully processed (not before)
- [ ] `QueChannel` for `committed_certificates` and `consensus_output` doesn't drop entries under load

## Subscriber Mode Transitions

The `Subscriber` component in `crates/consensus/executor/src/subscriber.rs` manages transitions between consensus participation modes:

```
CVV (Committee Voting Validator)
  │ ← Active consensus participation, produces headers, votes
  │
  ├─ Not in committee / epoch boundary trigger
  │
  v
NVV (Non-Voting Validator)
  │ ← Catch-up mode, processes committed certificates without voting
  │
  ├─ Falls behind committed round threshold
  │
  v
Observer
  │ ← Follow-only mode, subscribes to output channel
  │
  └─ Re-sync complete → back to NVV or CVV
```

### Coupled State
| State A | State B (coupled) | Coupling Invariant | Breaking Operation |
|---------|-------------------|-------------------|-------------------|
| `NodeMode` (CVV/NVV/Observer) | `consensus_output` channel consumer | Output source matches mode: CVV produces locally, NVV/Observer consumes from channel | Mode transition without switching output source |
| Subscriber committed round | Storage committed round | Subscriber doesn't skip epochs during mode transition | Mode change during epoch boundary processing |
| `ConsensusBus.node_mode` watch | Actual subscriber state | Watch reflects current mode for downstream consumers | Mode changes but watch not updated |

### Adversarial Sequences
- **CVV → NVV transition during epoch boundary** — If a validator transitions to NVV mid-epoch-close, partially processed epoch state could be inconsistent
- **NVV → CVV transition with stale state** — Validator re-enters consensus with outdated DAG. Must fully sync before participating
- **Observer → NVV with certificate gap** — Observer was following via output channel. Switching to NVV requires filling certificate gaps from peers. Missing certificates could stall sync
- **Rapid mode oscillation** — Repeated CVV↔NVV transitions if the validator is on the committee boundary. Each transition must cleanly drain/restart consensus state

### Output Finality Coordination
The subscriber coordinates between two output paths:
1. **Storage path:** Certificates committed to persistent storage
2. **Consensus output channel:** Committed certificates forwarded to execution

**Invariant:** Every certificate written to storage must eventually appear on the consensus output channel. A mode transition must not create a gap where storage has certificates that were never sent to execution.

### Audit Checklist
- [ ] Mode transitions drain in-flight certificates before switching output source
- [ ] No epoch is skipped during any mode transition sequence
- [ ] `node_mode` watch channel is updated atomically with the actual mode change
- [ ] CVV → NVV transition preserves the last committed round (no regression)
- [ ] Observer mode doesn't accumulate unbounded state while following

## Batch Builder and Validator Patterns

### Batch Builder (`crates/batch-builder/`)
The batch builder constructs transaction batches from the mempool for inclusion in consensus proposals.

**Key concerns:**
- **Transaction ordering within batches** — Ordering affects MEV extraction. Must be deterministic or policy-driven
- **Epoch-specific constraints** — Batches must respect epoch boundaries (e.g., system transactions only in epoch-closing blocks)
- **Worker-specific batches** — Each consensus worker builds independent batches. Cross-worker ordering is determined by DAG structure, not batch builder

### Batch Validator (`crates/batch-validator/`)
Validates batches received from peers before including them in the DAG.

**Coupled State:**
| State A | State B (coupled) | Coupling Invariant | Breaking Operation |
|---------|-------------------|-------------------|-------------------|
| Batch content (transactions) | Worker identity | Batch was built by the claimed worker | Forged worker identity in batch header |
| Batch epoch | Current consensus epoch | Batch is valid for the current epoch only | Stale-epoch batch accepted after epoch transition |
| Transaction validity | Chain state at batch time | Transactions were valid when batched | State changed between batch creation and execution |

### Audit Checklist
- [ ] Batch builder doesn't create batches spanning epoch boundaries
- [ ] Batch validation rejects batches from previous epochs
- [ ] Transaction ordering within a batch is deterministic across all validators
- [ ] Worker identity in batch header is cryptographically verified (not just asserted)
- [ ] Batch size is bounded to prevent DoS via oversized batches

## Storage Persistence Patterns

### Certificate Archival (`crates/storage/`)
Committed certificates are persisted for crash recovery and state sync.

**Key concerns:**

**Garbage Collection Interaction:**
```
Storage contains: certificates for rounds [gc_round - gc_depth ... latest_round]
GC deletes: certificates for rounds <= gc_round
Recovery reads: certificates from storage to rebuild DAG
```

If GC runs aggressively, recovery after a crash may find gaps in the certificate chain.

**Archive Indexing:**
- Certificates indexed by round and by authority
- Index must be consistent with actual stored certificates
- Race condition: certificate written but index not yet updated (crash between the two operations)

### Coupled State
| State A | State B (coupled) | Coupling Invariant | Breaking Operation |
|---------|-------------------|-------------------|-------------------|
| Certificate store (persisted) | DAG (in-memory) | DAG is a consistent subset of persisted certificates | Persist fails silently, DAG has entry with no backing store |
| Certificate store | GC round marker | No stored certificate has round <= gc_round | GC deletes certificate but marker not updated (or vice versa) |
| Archive index (round→certs) | Actual certificate data | Every index entry points to a valid certificate | Index written before certificate (crash = dangling index) |
| Storage committed round | Subscriber committed round | Storage is at least as fresh as subscriber's view | Subscriber advances but storage write fails |

### Recovery Patterns
- **Gap detection:** `construct_dag_from_cert_store()` rebuilds DAG from storage. Must handle gaps where GC deleted intermediate rounds
- **Partial write recovery:** If a certificate persist was interrupted (crash mid-write), the storage must detect and skip corrupt entries
- **Epoch boundary in storage:** Certificates from different epochs have different committees. Recovery must validate certificates against the correct epoch's committee

### Audit Checklist
- [ ] Certificate persist and index update are atomic (or ordered: certificate first, then index)
- [ ] GC does not delete certificates that pending sync requests reference
- [ ] Recovery path handles gaps gracefully (doesn't panic on missing parents)
- [ ] Storage writes are durable before the certificate is reported as committed
- [ ] Archive queries handle the race between write and index update
