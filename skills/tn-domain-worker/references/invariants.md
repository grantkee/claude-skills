# Worker-domain invariants

## I-1: `Batch.epoch` matches active consensus epoch

Worker observes epoch transitions via consensus bus and stops building stale-epoch batches at the boundary. Stale or future-epoch batches are rejected by validating peers.

## I-2: Beneficiary is in active committee for batch's epoch

Validation must check committee membership for `batch.epoch` (not the local node's current epoch). Cross-references `tn-domain-consensus` I-1.

## I-3: Base fee chains EIP-1559 from prior batch in same epoch

`new_fee = prev_fee * (1 ± (gas_used - gas_target) / adjustment_factor)`. Strategy (`Static` vs `Eip1559`) pinned at closing block of prior epoch.

## I-4: Blob transactions rejected at ingest

EIP-4844 blob txs are not supported. Reject at txn-pool entry and at peer-batch validation, not at execute.

## I-5: Bounded resources at every ingress

Txn pool: bounded by total bytes, sender count, per-sender count. Batch construction: bounded by tx count and bytes. Peer batch acceptance: bounded by pending fetches and per-peer rate.
