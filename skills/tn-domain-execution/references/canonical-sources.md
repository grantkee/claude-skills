# Execution-domain canonical sources — full lookup

## Reading EVM state

| Value | Source | Why this and not other sources |
|---|---|---|
| State at block N | `reth_env.state_at_block(N)` after confirming N exists via `header_by_number(N)` | Implicit canonical-tip reads return a different block than you intended whenever the engine has advanced |
| Header at block N | `reth_env.header_by_number(N)?` (handle `None` explicitly) | `finalized_header()` returns "some" finalized block, not block N |
| Latest finalized header | `reth_env.finalized_header()?` — only when "some recent finalized block" is what you genuinely want | Anywhere protocol-critical |
| Contract storage at boundary | `reth_env.get_worker_fee_configs_at(closing_final_height, ...)` and friends | Tip-reading variants leak post-boundary mutations |

## Engine cursors and progress

| Value | Source | Why this and not other sources |
|---|---|---|
| Highest executed consensus number | `engine.last_executed_consensus_number()` | The engine is the only authoritative source; downstream caches go stale |
| Recent blocks watch | `consensus_bus.recent_blocks().borrow()` | Channel updates are the only push source; polling other state risks misses |
| Engine update stream | `engine_update_rx` mpsc receiver | Out-of-band reads of engine state risk skipping updates |

## Block construction inputs

| Value | Source | Why this and not other sources |
|---|---|---|
| Block timestamp | `consensus_output.committed_at` | `SystemTime::now()` is non-deterministic across nodes |
| Transaction order | The order in `consensus_output.batches`, walking batches in committed order | HashMap, txn-pool insertion order, or any unordered collection diverges across nodes |
| Beneficiary | Leader of the consensus round, validated against committee at boundary | Local config, RPC input, or per-block heuristic |
| Base fee for opening block of new epoch | `header.base_fee_per_gas` of last block of closing epoch | Default fallback values; canonical tip; opening-block height (may not exist yet) |
| Gas limit | Protocol parameter pinned at epoch boundary | Live contract storage |

## System calls at boundary

| Value | Source | Why this and not other sources |
|---|---|---|
| `applyIncentives` input (rewards) | `gas_accumulator.rewards_counter()` snapshot at close | Live counter (may still be mutating) |
| `concludeEpoch` input (new committee) | Determined by stake state *before* incentives apply | Stake state after incentives have credited — that's the new committee, not the *next* committee |
| `applySlashes` input | Slash list resolved from consensus during the closing window | Any local list; slashes are consensus-driven |

## Anti-patterns: sources that look canonical but aren't

- `reth_env.finalized_header()` for protocol-critical computation
- `reth_env.get_worker_fee_configs(...)` (no height) for boundary reads
- Any iteration over `HashMap`/`HashSet` near block construction
- `SystemTime::now()` anywhere in the execution path
- `last_forwarded_consensus_number` as a stand-in for execution progress
- Cached engine state used after an `.await` without re-read
