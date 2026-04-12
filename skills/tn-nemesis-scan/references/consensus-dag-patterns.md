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
