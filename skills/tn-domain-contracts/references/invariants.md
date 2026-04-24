# Contracts-domain invariants

## I-1: System calls fire exactly once at intended boundary
`concludeEpoch` once per closing block; `applyIncentives` once per closing block; `applySlashes` per consensus-dictated occasion. Double-fire or miss corrupts registry.

## I-2: `applyIncentives` before `concludeEpoch`
Incentives credit closing committee using closing stake versions; conclude then transitions. Reverse order pays new committee with new versions — wrong.

## I-3: `applySlashes` at consensus-dictated position
Typically before incentives if slashes occurred. Position comes from consensus output.

## I-4: System-call inputs from authoritative state
New committee from on-chain stake (post-slash); rewards from gas accumulator snapshot; slashes from consensus evidence. Never local config or heuristic.

## I-5: Contract reads pinned to block height
Reading committee/stake/config for epoch N must be at the closing-block height of N. Cross-references `tn-domain-epoch` I-1 and `tn-domain-execution` I-2.
