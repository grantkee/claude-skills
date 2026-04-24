# Worker-domain bug patterns

## P-1: Stale-epoch batch on transition
Pipeline still in flight when epoch advances. Drain at boundary detection.

## P-2: Missing beneficiary committee check on peer batch
Validate `batch.beneficiary ∈ committee(batch.epoch)` before storage.

## P-3: Unbounded txn pool
Cap by bytes + sender count + per-sender count. Evict by fee.

## P-4: Blob tx leak
Explicit reject at ingest; type check before any other processing.

## P-5: Base fee from canonical-tip worker config (echo of `catchup_accumulator`)
Read worker fee config from closing-epoch final block state.

## P-6: Pool tx validated once, executed later under different state
Re-validate at batch construction (gas check, sender balance) — state may have advanced.
