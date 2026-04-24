---
name: tn-domain-storage
description: |
  Domain expert reference for the storage layer of telcoin-network — consensus DB (REDB),
  reth-db (MDBX), key encoding, table layout, atomic writes, and epoch-scoped vs persistent
  table lifecycle.
  Loaded by tn-rust-engineer and tn-domain-reviewer agents when work touches the
  Database trait, table definitions, key/value encoding, snapshot logic, or any code path
  that reads or writes the consensus DB or epoch records.
  Teaches the rules that keep consensus and execution storage internally consistent.
  NOT user-invocable. Loaded programmatically by tn-* agents via the Skill tool.
---

# tn-domain-storage

The storage layer in telcoin-network spans two databases: a consensus DB (REDB) for headers/certificates/votes/epoch records, and the reth DB (MDBX) for EVM state. Both must be internally consistent and consistent with each other at consensus boundaries — a partial write that crashes between two related rows can leave the node unable to safely continue.

If you are about to modify code that:

- lives under `crates/storage/**` or touches the `Database` trait
- defines or modifies tables, keys, value encodings, or migrations
- writes related rows that must be atomic (cert + header, header + votes, epoch record + finalized state)
- handles startup recovery, snapshot/restore, or table iteration
- changes serialization formats (bincode/bcs/ssz/etc.)

…load this skill before writing a single line.

## Why storage is different

Two rows that look independent — a certificate and its header, an epoch record and the corresponding committee — are usually load-bearing for each other. Half a write is worse than none: it makes the node *think* a piece of state exists when its dependencies don't. Crash safety is the whole game.

The other pitfall is encoding drift. Two functions encoding "the same" key with different routines (bincode vs bcs vs raw bytes) produce different byte sequences. Reads using the wrong encoding return `None` while the data sits in the table.

## Invariants

1. **Co-stored rows are written in one transaction.** Cert + header, header + votes, epoch record + closing-block hash, batch + batch index — every set of mutually-dependent rows must be inside one atomic write. Multi-step inserts that crash mid-way leave the node in a torn state.

2. **One key encoding per table, documented.** Each table has exactly one canonical key encoding. Switching encodings requires a migration, not a clever fallback. Reads and writes must use the same routine.

3. **Epoch-scoped tables reset on `RunEpochMode::NewEpoch`; persistent tables never reset.** Tables holding live consensus state (in-flight votes, parent references, leader candidates) get cleared when the epoch closes. Tables holding history (certificates, headers, epoch records) are never cleared.

4. **Iteration over a table for replay must produce items in canonical order.** Order is determined by key encoding plus the table's ordering rule. Any code that depends on iteration order must use a key whose encoding produces the desired order.

5. **The consensus DB and reth DB advance together at the boundary.** When the closing block of epoch N finalizes in reth, the corresponding `EpochRecord` for epoch N must be written in the consensus DB. A crash between these two writes leaves the node ambiguous about which epoch finished.

## Pre-write Checklist

1. **What rows depend on this write?** Name them. If any other row would become invalid (or surprisingly valid) without this one, you need an atomic write — bundle them.

2. **What's the key encoding?** Match the existing routine for this table. If you're adding a new table, document the encoding in the table definition.

3. **Is this table epoch-scoped or persistent?** If epoch-scoped, when does it reset? If persistent, what guarantees old rows don't leak into new-epoch processing?

4. **Does iteration order matter?** If you depend on order during replay or sync, name the order and confirm the key encoding produces it.

5. **What if this write succeeds and the next one in the operation fails?** Trace the recovery path. If the answer is "we re-process the operation", confirm the operation is idempotent against the partial state.

6. **Did you use `bincode` (or `bcs`, etc.) consistently with the table's existing encoding?** Mixing encodings within one table silently corrupts reads.

## Canonical Sources

| Value | Source | Avoid |
|---|---|---|
| Database trait surface | `tn_storage::Database` | Direct REDB/MDBX handles outside the trait |
| Table definition | The table's `define_table!` (or equivalent) macro invocation | Ad-hoc reads/writes that bypass the table type |
| Key encoding | The encoding routine documented at the table definition | Inferring from a sibling table |
| Atomic write boundary | `db.write_txn(|txn| { ... })` (or equivalent) | Sequential `db.put` calls without transaction wrapping |
| Snapshot for recovery | The most recent fully-committed transaction | A partially-written sequence of rows |

## Common Bug Patterns

### Pattern 1: Non-atomic co-stored writes

```rust
// WRONG — cert and header are dependent; a crash between writes is corruption
self.db.put_cert(&cert)?;
self.db.put_header(&cert.header_digest(), &header)?;
```

The fix: open a transaction, write both, commit:

```rust
self.db.write_txn(|txn| {
    txn.put_cert(&cert)?;
    txn.put_header(&cert.header_digest(), &header)?;
    Ok(())
})?;
```

### Pattern 2: Key encoding mismatch

```rust
// One module writes with bincode
let key = bincode::serialize(&(epoch, round))?;
self.db.put(table, &key, &value)?;

// Another module reads with bcs — silent miss
let key = bcs::to_bytes(&(epoch, round))?;
let value = self.db.get(table, &key)?; // None, despite data existing
```

The fix: pick one encoding per table, document it at the table definition, route all reads/writes through a typed wrapper that uses that encoding.

### Pattern 3: Epoch-scoped table not reset

```rust
// WRONG — in-flight vote table carries votes from epoch N into epoch N+1
match run_epoch_mode {
    RunEpochMode::NewEpoch => {
        // forgot to clear pending_votes
    }
}
```

The fix: enumerate every epoch-scoped table and reset each one on `NewEpoch`. (Cross-references `tn-domain-epoch` invariant I-3.)

### Pattern 4: Iteration relies on insertion order

```rust
// WRONG — iteration order depends on key encoding, not insertion
for (key, val) in table.iter()? {
    if !is_first_seen(key) { ... }
}
```

The fix: derive a key encoding that produces the order you need, or sort explicitly after collecting.

## Further Reading

- `references/invariants.md`
- `references/bug-patterns.md`
- `references/canonical-sources.md`
