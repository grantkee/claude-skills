# Storage-domain canonical sources

## Database surfaces

| Value | Source | Avoid |
|---|---|---|
| Consensus DB handle | `tn_storage::Database` impl returned by `open_db` | Direct REDB handles |
| Reth DB handle | Reth's database via `RethDb` / `RethEnv` | Direct MDBX handles |
| Atomic write | `db.write_txn(|txn| { ... })` | Sequential puts without txn |
| Read-only scan | `db.read_txn(|txn| { ... })` | Mixing reads inside a write txn unless required |

## Encoding choices

| Value | Encoding | Avoid |
|---|---|---|
| Cross-validator key (consensus) | bincode (canonical) | bcs/json/inline byte concatenation |
| Cross-EVM key/value | EVM-defined (RLP for tx, etc.) | Other encodings without explicit purpose |
| Numerical-order key (e.g., consensus_number) | Big-endian u64 | Little-endian (breaks numerical iter order) |
| Composite key | Document the order; encode tuple deterministically | Inline string concat |

## Lifecycle classification

| Table | Lifecycle | Reset trigger |
|---|---|---|
| Certificates, headers | Persistent | Never |
| Epoch records | Persistent | Never |
| Pending votes, parent staging | Epoch-scoped | `RunEpochMode::NewEpoch` |
| Leader-counter cache | Epoch-scoped | `NewEpoch` |
| Reth canonical chain | Persistent | Never (reorgs are surgical, not resets) |

When you add a table, place it explicitly in this classification.
