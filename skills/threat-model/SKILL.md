---
name: threat-model
description: |
  Generate security threat model documentation for telcoin-network components.
  Trigger on: "threat model", "attack surface", "security architecture", "adversary model", "security doc", "audit prep"
---

# Threat Model Generator

Generate structured security threat model documentation for the telcoin-network repo -- a Rust blockchain node combining Narwhal/Bullshark DAG-based BFT consensus with EVM execution via Reth.

## Project Context

Telcoin Network is a permissioned-set (staked validator) blockchain that separates:

- **Consensus layer**: DAG-based BFT (Narwhal/Bullshark) with BLS12-381 signatures, organized into primaries (certificate DAG) and workers (batch broadcasting).
- **Execution layer**: Reth-based EVM with custom precompiles (TEL native ERC-20 at `0x7e1`) and system calls for epoch/committee management.
- **Networking layer**: libp2p with gossipsub, request-response, Kademlia DHT, and QUIC transport. Peer scoring and banning via `PeerManager`.
- **Synchronization**: Trustless sync from genesis via an Epoch Chain (BLS-signed epoch records) and a Consensus Chain (verified consensus headers). See `SYNC.md`.

Key invariants:
- Byzantine fault tolerance: tolerates f < n/3 faulty validators.
- Quorum threshold: 2f+1 (calculated as `2*n/3 + 1`). See `crates/types/src/committee.rs`.
- Validity threshold: f+1 (calculated as `ceil(n/3)`).
- All validators have equal voting power (`EQUAL_VOTING_POWER = 1`).
- Only current committee members may publish on gossipsub consensus topics.
- System calls use a dedicated `SYSTEM_ADDRESS` (`0xfffe...fe`) and are not callable by external accounts.
- TEL precompile governance operations are restricted to `GOVERNANCE_SAFE_ADDRESS`.

## Process

When asked to generate a threat model, follow these phases:

### Phase 1: Scope

Determine which component or subsystem to model. Ask the user if unclear. Options include:
- Full system (high-level)
- Consensus (primary DAG, certificate aggregation, Bullshark ordering)
- Networking (libp2p, gossipsub, peer management, Kademlia)
- Execution (EVM, precompiles, system calls, transaction pool)
- Synchronization (epoch chain, consensus chain, state sync)
- RPC (external API surface)
- A specific crate (e.g., `crates/network-libp2p/`, `crates/consensus/primary/`)

### Phase 2: Map Trust Boundaries and Entry Points

Identify all points where untrusted data enters the system. Key entry points in this codebase:

1. **Gossipsub messages** (`crates/network-libp2p/src/consensus.rs`) -- certificates, batch announcements, consensus output results. Only committee members should publish. Validated via BLS signature before propagation.
2. **Request-response messages** (`crates/consensus/primary/src/network/`) -- vote requests, missing certificate requests, consensus output requests, epoch record requests. Handled by `RequestHandler` in `handler.rs`.
3. **RPC endpoints** (`crates/execution/tn-rpc/`) -- `tn_latestConsensusHeader`, `tn_genesis`, `tn_epochRecord`, `tn_epochRecordByHash`. Plus standard Reth JSON-RPC (eth, debug, trace).
4. **Transaction pool** (`crates/tn-reth/src/txn_pool.rs`) -- user-submitted transactions entering the mempool.
5. **Worker batch broadcasts** -- batches of transactions from workers to primaries.
6. **Kademlia DHT** -- `NodeRecord` publication for peer discovery. Committee validators publish records keyed by BLS public key.
7. **Stream-based sync** (`StreamBehavior` in the libp2p network) -- bulk data transfer for state sync.

For each entry point, read the relevant handler code and document:
- What data is received
- What validation occurs before processing
- What happens on validation failure (penalty, disconnect, ignore)
- Whether the handler is rate-limited or bounded

### Phase 3: Identify Adversary Model and Capabilities

Document the adversary model derived from the protocol's BFT assumptions:

- **Byzantine validators**: Up to f = floor((n-1)/3) validators may be arbitrarily malicious. They can equivocate (sign conflicting messages), withhold messages, or send malformed data.
- **Network adversary**: Can delay, reorder, or drop messages between honest nodes. Cannot forge BLS signatures.
- **External attacker**: No committee membership. Can send transactions via RPC, attempt to connect as a peer, submit malformed requests.
- **Compromised key**: A validator's BLS keypair is compromised. Attacker can sign valid messages as that validator.

Search for specific adversary handling:
- Equivocation detection: `auth_last_vote` map in `RequestHandler` tracks last vote per authority to detect equivocation early.
- Behind-consensus detection: `behind_consensus()` in handler detects when a node is too far behind and switches to catchup mode.
- Committee verification: `get_committee()` validates messages against the correct epoch's committee.

### Phase 4: Enumerate Attack Vectors per Component

For each component in scope, enumerate concrete attacks. Use subagents to explore code in parallel. Key vectors to investigate:

**Consensus attacks**:
- Certificate forgery (forge BLS aggregate signatures)
- Equivocation (sign conflicting headers for the same round)
- Parent withholding (withhold certificates to slow DAG progress)
- Round manipulation (propose headers with inflated round numbers)
- GC window exploitation (exploit the garbage collection depth boundary)

**Networking attacks**:
- Message flooding (overwhelm gossipsub with valid-looking messages)
- Gossipsub amplification (exploit mesh propagation)
- Peer score gaming (manipulate scoring to avoid bans while being malicious)
- Sybil via Kademlia (flood DHT with fake node records)
- Eclipse attack (isolate a validator from honest peers)

**Execution attacks**:
- Malformed batch injection (batches with invalid transactions)
- System call spoofing (attempt to call system-only functions from external accounts)
- TEL precompile exploits (governance function access, timelock bypass if `faucet` feature leaks to mainnet)
- Gas cost undercharging (some precompile operations are undercharged vs EVM equivalent -- see TEL precompile README gas tables)
- Transaction pool resource exhaustion

**Sync attacks**:
- Epoch record forgery (provide fake epoch records during sync)
- Consensus header manipulation (omit or reorder consensus headers)
- Stale committee injection (serve outdated committee data to syncing nodes)

### Phase 5: Catalog Existing Security Controls

Search the codebase for these control categories and document what exists:

1. **BLS signature verification**: `verify_cert()`, `verify_signature()`, `verify_secure()` in `crates/types/src/crypto/`. Certificates require quorum (2f+1) valid BLS signatures. Aggregate signature verification via `BlsAggregateSignature`.
2. **Peer banning and scoring**: `PeerManager` in `crates/network-libp2p/src/peers/`. Penalty levels: `Mild` (~50 before ban), `Medium` (~10 before ban), `Severe` (~5 before ban), `Fatal` (immediate ban). Score decay over time. Temporary ban cache prevents immediate reconnection.
3. **System call access control**: `SYSTEM_ADDRESS` in `crates/tn-reth/src/system_calls.rs`. EVM handler checks caller is system address. `SystemCallable.sol` in contracts enforces on-chain.
4. **TEL precompile guards**: Governance-only functions check `GOVERNANCE_SAFE_ADDRESS`. Timelock on mainnet mints (7-day). Signature malleability rejection in `permit`. Double-claim prevention.
5. **Gossipsub message validation**: Source peer must be a staked validator. Invalid messages trigger `Penalty` via `PeerManager`. Topic validation ensures messages arrive on correct topics.
6. **Equivocation detection**: `auth_last_vote` map in `RequestHandler` caches last vote per authority with epoch, round, and header digest.
7. **Network behavior ordering**: `TNBehavior` struct places `peer_manager` first so banned-peer connection denials fire before other behaviors register the connection.
8. **Epoch chain verification**: Syncing nodes verify each epoch record's BLS certificate (2/3+1 signatures) and chain the records via parent hashes. See `SYNC.md`.

### Phase 6: Identify Gaps

Search for known weakness patterns and flag them:

1. **HashMap in consensus paths**: `HashMap` is used in several consensus-critical data structures (e.g., `RequestHandler` fields, `batch_fetcher.rs`). HashMaps use SipHash which is DoS-resistant, but ordering non-determinism could cause subtle consensus divergence if iteration order matters. Grep `crates/consensus/` for `HashMap` usage.
2. **Unbounded channels**: Search for `unbounded_channel` in consensus paths (`crates/consensus/primary/src/certificate_fetcher.rs`, `crates/consensus/primary/src/certifier.rs`). Unbounded channels can be exploited for memory exhaustion if a malicious peer floods the receiver.
3. **Gas undercharging in precompile**: The TEL precompile README documents that `approve`, `mint` (mainnet), `burn`, and `grantMintRole` are undercharged relative to worst-case EVM cost. This means these operations are subsidized, which could be exploited for gas-based DoS.
4. **Peer reputation metric gaps**: Check if peer scoring captures all penalty-worthy behaviors. Look for error paths in network handlers that do NOT assess a penalty.
5. **Rate limiting on RPC**: Check whether the `tn_*` RPC endpoints have rate limiting or request size bounds.
6. **Kademlia record validation**: Verify that DHT records are validated (BLS key ownership) before being accepted.
7. **Total supply accounting drift**: TEL `totalSupply` does not account for native balance changes outside the precompile (gas fees, coinbase rewards). Off-chain indexers must reconcile.

### Phase 7: Generate the Threat Model Document

Produce the final document using the output format below. Write it to a location agreed with the user (e.g., `docs/threat-model.md` or `tasks/threat-model-{component}.md`).

## Output Format

The generated threat model document MUST follow this structure:

```markdown
# Threat Model: {Component/Scope}

Generated: {date}
Scope: {what was analyzed}
Commit: {git short hash}

## System Overview

Brief architectural description of the component being modeled.
Include a data flow summary showing how messages/data enter and exit the component.

## Trust Boundaries

| Boundary | Inside (Trusted) | Outside (Untrusted) | Crossing Mechanism |
|----------|-------------------|---------------------|--------------------|
| ...      | ...               | ...                 | ...                |

## Adversary Model

- **Byzantine validators (f < n/3)**: capabilities and constraints
- **Network adversary**: what they can and cannot do
- **External attacker**: no committee keys, limited to RPC/P2P connection
- **Key compromise**: single validator key leaked

## Attack Surface

### {Component 1}

| # | Attack Vector | Entry Point | Preconditions | Impact | Likelihood | Severity |
|---|---------------|-------------|---------------|--------|------------|----------|
| 1 | ...           | ...         | ...           | ...    | ...        | ...      |

### {Component 2}
...

## Security Properties

What MUST hold for the system to be correct:
- [ ] Property 1 (e.g., "No certificate accepted without 2f+1 valid BLS signatures")
- [ ] Property 2
- ...

## Controls Inventory

| Control | Location | Protects Against | Status |
|---------|----------|------------------|--------|
| ...     | ...      | ...              | ...    |

## Gaps and Recommendations

| # | Gap | Risk | Recommendation | Priority |
|---|-----|------|----------------|----------|
| 1 | ... | ...  | ...            | ...      |
```

## Component Reference

Key components and their security-relevant aspects for quick lookup during threat modeling.

### Consensus

| Aspect | Location | Security Relevance |
|--------|----------|--------------------|
| Committee & quorum | `crates/types/src/committee.rs` | Quorum = 2n/3+1, validity = ceil(n/3). Equal voting power. |
| Certificate verification | `crates/types/src/primary/certificate.rs` | `verify_cert()` checks quorum weight + BLS aggregate sig. |
| BLS crypto | `crates/types/src/crypto/bls_signature.rs` | `verify_secure()`, `verify_raw()`, proof of possession. |
| Primary network handler | `crates/consensus/primary/src/network/handler.rs` | Processes votes, cert requests, gossip. Equivocation detection via `auth_last_vote`. |
| Certifier | `crates/consensus/primary/src/certifier.rs` | Aggregates votes into certificates. |
| Certificate fetcher | `crates/consensus/primary/src/certificate_fetcher.rs` | Fetches missing certs from peers. |
| Cert validator | `crates/consensus/primary/src/state_sync/cert_validator.rs` | Validates certificate chunks during sync. |
| Bullshark consensus | `crates/consensus/primary/src/consensus/` | Leader election, commit logic. |
| Worker batch handling | `crates/consensus/worker/src/worker.rs` | Batch creation and forwarding. |
| Quorum waiter | `crates/consensus/worker/src/quorum_waiter.rs` | Waits for validity threshold on batch broadcasts. |
| Consensus subscriber | `crates/consensus/executor/src/subscriber.rs` | Receives committed sub-DAGs for execution. |

### Networking

| Aspect | Location | Security Relevance |
|--------|----------|--------------------|
| Network behavior | `crates/network-libp2p/src/consensus.rs` | `TNBehavior` composes peer_manager, gossipsub, req_res, kademlia, stream. Peer manager is first for ban short-circuit. |
| Peer manager | `crates/network-libp2p/src/peers/manager.rs` | Tracks connected/banned peers. Handles dial, disconnect, ban events. |
| Peer scoring | `crates/network-libp2p/src/peers/score.rs` | Score range [-100, 100] with decay. Configurable thresholds. |
| Penalty types | `crates/network-libp2p/src/peers/types.rs` | `Mild`, `Medium`, `Severe`, `Fatal` penalty levels. |
| Ban cache | `crates/network-libp2p/src/peers/cache.rs` | LRU time-based temporary ban. Prevents immediate reconnection. |
| Gossipsub validation | `crates/network-libp2p/src/consensus.rs` | Only staked validators can publish. Source verified before propagation. |
| Kademlia DHT | `crates/network-libp2p/src/consensus.rs` | `NodeRecord` discovery keyed by BLS public key. |

### Execution

| Aspect | Location | Security Relevance |
|--------|----------|--------------------|
| EVM handler | `crates/tn-reth/src/evm/handler.rs` | Custom basefee logic, gas limit penalty. |
| EVM block builder | `crates/tn-reth/src/evm/block.rs` | Block construction from consensus output. |
| System calls | `crates/tn-reth/src/system_calls.rs` | `SYSTEM_ADDRESS`, `CONSENSUS_REGISTRY_ADDRESS`. Epoch/committee management. |
| TEL precompile | `crates/tn-reth/src/evm/tel_precompile/` | Native ERC-20 at `0x7e1`. mint/claim/burn with governance guards. Timelock on mainnet. |
| TEL access control | `crates/tn-reth/src/evm/tel_precompile/mod.rs` | Governance-only: mint, burn, grantMintRole, revokeMintRole. |
| TEL permit (EIP-2612) | `crates/tn-reth/src/evm/tel_precompile/eip2612.rs` | Signature malleability rejection (s > SECP256K1N_HALF). |
| Transaction pool | `crates/tn-reth/src/txn_pool.rs` | Transaction validation before inclusion. |
| On-chain registry | `tn-contracts/src/consensus/ConsensusRegistry.sol` | Validator staking, status transitions, committee selection. |
| SystemCallable guard | `tn-contracts/src/consensus/SystemCallable.sol` | On-chain enforcement that only system address can call epoch transitions. |

### Storage

| Aspect | Location | Security Relevance |
|--------|----------|--------------------|
| Certificate store | `crates/storage/` | Persistent certificate storage. Integrity depends on write validation. |
| Consensus chain | `crates/storage/` (ConsensusChain) | Consensus header chain with parent hash linking. |
| Epoch chain | Epoch records with BLS certificates stored per-node. | Trustless verification chain from genesis. |
| Payload store | `crates/storage/` (PayloadStore) | Worker batch payloads. |

### RPC

| Aspect | Location | Security Relevance |
|--------|----------|--------------------|
| TN namespace | `crates/execution/tn-rpc/src/rpc_ext.rs` | `tn_latestConsensusHeader`, `tn_genesis`, `tn_epochRecord`, `tn_epochRecordByHash`. Read-only. |
| Standard Reth RPC | Via Reth node builder | eth, debug, trace, net namespaces. Reth's built-in rate limiting applies. |
| Engine API | Internal only | Consensus-to-execution communication. Not exposed externally. |

### Synchronization

| Aspect | Location | Security Relevance |
|--------|----------|--------------------|
| Epoch chain sync | `SYNC.md`, epoch handling in node manager | Trustless from genesis committee. Each epoch record verified by 2/3+1 BLS sigs from that epoch's committee. |
| Consensus chain sync | `SYNC.md`, consensus chain in storage | Headers chained by parent hash. Verified hash sources: execution blocks, epoch records, committee gossip. |
| State sync streams | `crates/network-libp2p/` StreamBehavior | Bulk data transfer. Needs authentication of data source. |

## Rules

1. ALWAYS read the actual source code before documenting a control or gap. Do not assume based on naming alone.
2. Use subagents to explore multiple crates in parallel when mapping attack surfaces.
3. When documenting an attack vector, include the specific code path an attacker would target (file + function).
4. For each gap, verify it is actually present by reading the code. Do not flag theoretical issues without evidence.
5. Severity ratings use: Critical (consensus break / fund loss), High (network partition / DoS), Medium (degraded performance / information leak), Low (minor / requires unlikely preconditions).
6. Likelihood ratings use: High (exploitable by external attacker with no special access), Medium (requires compromised validator or sustained effort), Low (requires multiple compromised validators or race conditions).
7. Always check the current git commit hash and include it in the output for reproducibility.
8. Cross-reference findings with `SECURITY.md` for responsible disclosure context.
9. Do not generate a threat model for out-of-scope items (third-party dApps, dependency vulnerabilities, social engineering). See `SECURITY.md` scope table.
10. When the user asks for "audit prep", generate the full-system threat model and additionally list the top 10 highest-priority items a security auditor should focus on.
11. Write the threat model document to the location the user specifies. Default to `tasks/threat-model-{scope}.md` if no location is given.
12. After generating, ask the user if they want to drill deeper into any specific component or attack vector.
