# Contracts-domain canonical sources

| Value | Source | Avoid |
|---|---|---|
| New committee | Computed from stake state after slashes apply | Local list; pre-slash stake |
| Rewards | `gas_accumulator.rewards_counter()` snapshot at close | Live counter |
| Slash list | Consensus output's slash field | Local heuristic |
| Validator activation/exit | `ValidatorInfo` in ConsensusRegistry | Local timing |
| Stake version (reward tier) | `StakeManager` versioning | Cached value |
| EpochInfo for past epoch N | Read at closing-block height of N | Live storage |
| ConsensusRegistry address | `0x07E17...` (system address constant) | Re-derive at runtime |
| ABI types | Pinned in `tn-reth` next to call site | Inline anonymous tuples |

## System-call ordering at closing block (canonical)

1. Per-block calls (any normal block-level system calls)
2. `applySlashes(slashes)` — if any slashes from this closing window
3. `applyIncentives(rewards)` — credits closing committee with closing-version stake
4. `concludeEpoch(newCommittee)` — transitions to new committee for epoch N+1
