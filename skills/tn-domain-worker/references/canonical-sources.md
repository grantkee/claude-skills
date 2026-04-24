# Worker-domain canonical sources

| Value | Source | Avoid |
|---|---|---|
| Active epoch | `consensus_bus.current_epoch().borrow()` | Local timestamp; primary RPC |
| Committee for batch's epoch | `EpochRecord` for `batch.epoch` | Live `ConsensusRegistry` |
| Beneficiary committee check | Membership in committee for `batch.epoch` | Local config |
| Worker fee strategy/params | Closing-epoch final block state | Live `WorkerConfigs` |
| Base fee at new epoch | Last batch's `base_fee_per_gas` of prior epoch | Defaults |
| Pool capacity | `tn_config` parameters | Implicit |
| Pending tx ordering | By sender + nonce, then by fee | HashMap iteration |
| Blob tx detection | `tx.tx_type() == TxType::Blob` (or eq.) | Field-presence heuristic |
