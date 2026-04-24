# Storage-domain bug patterns

## P-1: Cert + header non-atomic write

```rust
// WRONG
self.db.put_cert(cert)?;     // crash here = orphaned cert pointer
self.db.put_header(...)?;
```

Wrap in transaction.

## P-2: bincode/bcs encoding drift

Read site uses bcs, write site uses bincode (or vice versa). Lookups silently return None. Symptom: data "disappears" from a table that contains it.

Fix: typed table wrapper enforcing one encoding.

## P-3: Epoch-scoped table not reset

In-flight vote table carries epoch N's pending votes into epoch N+1. New-epoch validators see votes referencing prior committee. Symptom: spurious validation failures or accepting stale votes.

Fix: explicit list of epoch-scoped tables, reset each on `NewEpoch`.

## P-4: Inserting after partial recovery

On restart, code re-processes consensus outputs N..M. For an output that was *partially* written (cert stored, header missing), the re-process inserts the cert again, fails on a uniqueness check, and aborts.

Fix: idempotent inserts on the recovery path (`put_if_absent` or pre-check) plus a recovery cursor that resumes at the right output.

## P-5: Iteration with non-canonical key encoding

```rust
// keys encoded as little-endian u64 — iteration order is not numerical
for (key, val) in table.iter()? {
    process_in_order(key, val); // wrong order!
}
```

Use big-endian for numerical-iteration keys, or sort post-collection.
