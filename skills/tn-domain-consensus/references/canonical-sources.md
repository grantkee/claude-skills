# Consensus-domain canonical sources

## Committee and quorum

| Value | Source | Avoid |
|---|---|---|
| Committee for epoch N | `EpochRecord` for epoch N | Live `ConsensusRegistry` storage |
| `f` for epoch N | `(committee.size() - 1) / 3` | `n / 3` (off-by-one) |
| Quorum for epoch N | `2 * f + 1` | Hardcoded constant; `n / 2 + 1` |
| Stake-weighted quorum | Sum of stake of signers ≥ `2 * total_stake / 3 + 1` | Counting validators alone (ignores stake weights) |

## Certificates and headers

| Value | Source | Avoid |
|---|---|---|
| Cert validity | All signers in epoch's committee + signatures verify + parents validated + round monotonic | Signature check alone |
| Header validity | Author in committee + epoch matches + round monotonic + no prior header for `(author, round)` | Trust based on origin peer |
| Parent references | `cert.parents()` looked up in storage and validated | Trusting parents implicitly |
| Round R+1 readiness | `2f+1` certs stored for round R | Time-based advance |

## ConsensusOutput stream

| Value | Source | Avoid |
|---|---|---|
| Next consensus_number | `engine.last_executed_consensus_number() + 1` | Local cursor; `last_forwarded_consensus_number` |
| Output ordering | Strictly increasing by `consensus_number` | Out-of-band reordering, parallel emission |
| Replay window | `[engine.last_executed + 1, consensus_chain.last_committed]` | Any other bounds |

## Signing payloads

| Value | Source | Avoid |
|---|---|---|
| Vote payload | `(epoch, round, header_digest)` triple, BLS-aggregated | `header_digest` alone (replay across epochs) |
| Cert payload | `(epoch, round, set_of_parent_digests, header_digest)` | Anything missing epoch |
| Hash function | `keccak256` for cross-EVM payloads, `blake3` internally | Mixing without explicit purpose |
