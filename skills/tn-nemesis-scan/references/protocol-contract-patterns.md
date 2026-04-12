# Protocol-Contract Interaction Patterns

Reference file for the Nemesis auditor. Load when auditing Rust protocol code that interacts with Solidity contracts at epoch boundaries, or when auditing ConsensusRegistry / StakeManager contracts.

## Epoch Boundary System Call Sequence

The epoch closing sequence is a strict ordering of Rust → Solidity system calls. Ordering violations break reward distribution or committee rotation.

```
Block execution detects close_epoch flag (TNBlockExecutionCtx.close_epoch: Option<B256>)
  │
  ├─ 1. apply_consensus_block_rewards()
  │     └─ Encodes RewardInfo[] from RewardsCounter
  │     └─ Calls applyIncentives(RewardInfo[]) on ConsensusRegistry
  │     └─ Solidity: weighted rewards = stakeAmount * consensusHeaderCount
  │     └─ Solidity: updates balances[validator] with pro-rata share of epochIssuance
  │     └─ Solidity: rolls dust to undistributedIssuance
  │
  ├─ 2. shuffle_new_committee()
  │     └─ Reads active validators from chain state via getValidators(Active)
  │     └─ Reads nextCommitteeSize from ConsensusRegistry
  │     └─ region_aware_shuffle(): round-robin region selection + Fisher-Yates intra-region
  │     └─ Deterministic shuffle seeded by BLS signature hash (close_epoch value)
  │
  └─ 3. apply_closing_epoch_contract_call()
        └─ Encodes concludeEpochCall with shuffled committee
        └─ Calls concludeEpoch(address[] futureCommittee) on ConsensusRegistry
        └─ Solidity: validates committee sorting and size
        └─ Solidity: calls _updateValidatorQueue() — activates PendingActivation, exits PendingExit
        └─ Solidity: rotates epochPointer = (epochPointer + 1) % 4
        └─ Solidity: increments currentEpoch
```

**CRITICAL ORDERING INVARIANT:** `applyIncentives()` MUST execute before `concludeEpoch()`. If reversed:
- Rewards are applied to the wrong epoch's committee (validators already rotated)
- PendingExit validators may have already been exited, missing their final reward

**Key files:**
- `crates/tn-reth/src/evm/block.rs` — Rust-side epoch closing logic
- `crates/tn-reth/src/system_calls.rs` — Solidity interface definitions and EpochState cache
- `tn-contracts/src/consensus/ConsensusRegistry.sol` — On-chain epoch state machine

## Cross-Boundary Coupled State Pairs

These pairs span the Rust/Solidity boundary. A mutation on one side without corresponding update on the other causes silent divergence.

| Rust State | Solidity State | Coupling Invariant | Breaking Operation |
|-----------|---------------|-------------------|-------------------|
| `RewardsCounter` (block leader counts) | `balances[validator]` | Sum of RewardInfo.consensusHeaderCount must equal total blocks produced in epoch | RewardInfo array with wrong validator subset or count |
| `TNBlockExecutionCtx.close_epoch` flag | `currentEpoch` counter | Epoch closes exactly once per epoch boundary | Missing or duplicate close_epoch flag |
| Shuffled committee from `shuffle_new_committee()` | `epochInfo[epochPointer].committee` | Identical validator set and order | Non-deterministic shuffle seed, different active validator read |
| `EpochState.epoch_info` (Rust cache) | `epochInfo[epochPointer]` (Solidity ring buffer) | Cache reflects current on-chain state | Stale cache across epoch boundary |
| Rust epoch boundary timestamp (`epoch_start + epochDuration`) | `versions[stakeVersion].epochDuration` | Rust and Solidity agree on when epoch ends | epochDuration changed via governance mid-epoch |
| Gas accumulator / block rewards | `undistributedIssuance` dust rollover | Rust doesn't track dust — Solidity silently rolls it forward | Issuance audit expects exact accounting but dust accumulates |

## Validator Lifecycle State Machine

Transitions happen in `_updateValidatorQueue()` during `concludeEpoch()`. Each status has invariants that must hold.

```
Undefined ──stake()──> Staked ──activate()──> PendingActivation
                                                    │
                                          concludeEpoch() calls _activate()
                                                    │
                                                    v
                                                 Active ──beginExit()──> PendingExit
                                                                            │
                                                                  concludeEpoch() calls _exit()
                                                                  (only if not in next 3 committees)
                                                                            │
                                                                            v
                                                                         Exited ──unstake()──> (removed)
                                                                            │
                                                                      _retire() can mark isRetired=true
                                                                      _consensusBurn() = _exit + _retire + _unstake + confiscate
```

**Invariants per status:**
- **Staked**: Has ConsensusNFT, deposited stakeAmount, NOT in any committee
- **PendingActivation**: Will become Active at next concludeEpoch, NOT yet in committee
- **Active**: In committee rotation pool, eligible for rewards, CAN beginExit
- **PendingExit**: Still in current committee (up to 3 more epochs), still earns rewards until fully exited
- **Exited**: No longer in committee, CAN unstake after exitEpoch
- **Retired** (flag): Cannot re-activate, excluded from consensus permanently

**Adversarial sequences targeting lifecycle:**
- `activate()` + immediate `beginExit()` before next `concludeEpoch()` — validator never serves but occupies a committee slot?
- `beginExit()` during epoch N, but committee includes them for epochs N+1, N+2, N+3 — do they still earn rewards for those epochs?
- `_consensusBurn()` on a validator in PendingExit — does _exit + _retire + _unstake handle the partial state correctly?
- Slash a validator in PendingActivation — they haven't served yet, should they be slashable?

## Ring Buffer Indexing Patterns

ConsensusRegistry uses a 4-slot ring buffer for epoch history. Off-by-one errors here cause consensus forks.

```
epochPointer:     0    1    2    3    0    1    ...
                  ↑                   ↑
              epoch N            epoch N+4 (overwrites N)

epochInfo[epochPointer]       = current epoch's info
epochInfo[(epochPointer+3)%4] = oldest available epoch (about to be overwritten)
futureEpochInfo[4]            = next 2 epochs' committees (separate ring)
```

**Audit checklist for ring buffer:**
- [ ] Every read of `epochInfo[i]` uses `epochPointer` or `(epochPointer + offset) % 4` correctly
- [ ] `concludeEpoch()` increments `epochPointer` AFTER writing new epoch data (not before)
- [ ] No path reads `epochInfo` between the pointer increment and the data write (TOCTOU)
- [ ] `futureEpochInfo` indexing is independent of `epochInfo` indexing — verify no shared pointer
- [ ] Epoch info for epoch N-4 is truly unreachable (no stale reference holds it)

## ConsensusRegistry Access Control Audit Checklist

System calls (from block execution) vs governance calls vs user calls have different trust models.

| Function | Caller | Access Control | Audit Focus |
|----------|--------|---------------|-------------|
| `concludeEpoch()` | Block executor (system) | `onlySystemCall` modifier | Can it be called from a transaction? |
| `applyIncentives()` | Block executor (system) | `onlySystemCall` modifier | Can RewardInfo be spoofed? |
| `applySlashes()` | Block executor (system) | `onlySystemCall` modifier | Can slash amounts be manipulated? |
| `stake()` | Validator (user) | Requires ConsensusNFT + exact stakeAmount | Can stake without NFT? Can double-stake? |
| `activate()` | Validator (user) | Must be Staked status | Can activate from wrong status? |
| `beginExit()` | Validator (user) | Must be Active status | Can exit from wrong status? |
| `unstake()` | Validator (user) | Must be Exited + past exitEpoch | Can unstake early? |
| `mint()` | Governance | `onlyRole(GOVERNANCE_ROLE)` | Can non-governance mint? |
| `burn()` | Governance | `onlyRole(GOVERNANCE_ROLE)` | Does burn handle all validator states? |
| `claimStakeRewards()` | Validator (user) | Balance check on `balances[validator]` | Can claim more than balance? |

## Reward Distribution Accounting

The reward calculation in `applyIncentives()` uses weighted distribution:

```
For each validator in RewardInfo[]:
  weight = stakeAmount * consensusHeaderCount
  totalWeight += weight

For each validator:
  reward = (weight / totalWeight) * (epochIssuance + undistributedIssuance)
  balances[validator] += reward

undistributedIssuance = remainder (dust from integer division)
```

**Audit focus areas:**
- [ ] Integer division ordering: is `(weight * totalIssuance) / totalWeight` or `weight / totalWeight * totalIssuance`? The latter loses precision
- [ ] Sum of all distributed rewards + new undistributedIssuance == epochIssuance + old undistributedIssuance (conservation)
- [ ] What happens if RewardInfo[] is empty? (No blocks produced in epoch — all issuance becomes undistributed?)
- [ ] What if a validator in RewardInfo[] has status != Active? (Exited validator still gets rewards?)
- [ ] `stakeVersion` lookup: does the weight calculation use the validator's stakeVersion or the current global stakeVersion?
- [ ] Can `totalWeight` be zero? (Division by zero if no validators have stake)

## Adversarial Epoch Boundary Sequences

These exploit the gap between Rust state changes and Solidity state changes at epoch transitions:

- **Slash + concludeEpoch in same block** — Does slash execute before or after reward distribution? Before or after committee rotation?
- **Governance burn() during epoch boundary** — _consensusBurn calls _exit + _retire + _unstake. If concludeEpoch is in the same block, which executes first?
- **stakeVersion change mid-epoch** — epochIssuance and stakeAmount change. Rewards for blocks already produced use old or new values?
- **Empty RewardInfo array** — If no blocks produced, does all issuance roll to undistributed? Is this recoverable?
- **Duplicate validator in RewardInfo** — Does applyIncentives check for uniqueness? Double-counting inflates rewards
- **Committee with validator who exited between shuffle and conclude** — Shuffle reads Active validators, but beginExit() could have been called in a block between shuffle and conclude

## Region-Aware Committee Shuffle

The committee shuffle uses geographic region diversity to distribute validators across the committee. Implemented in `crates/tn-reth/src/evm/block.rs` (`region_aware_shuffle`).

### Algorithm
```
1. Separate active validators into region buckets (region 1-8) and unassigned (region 0)
2. If no regions assigned → fallback to plain Fisher-Yates shuffle (deterministic via BLS sig hash seed)
3. Otherwise:
   a. Fisher-Yates shuffle WITHIN each region bucket (intra-region randomization)
   b. Round-robin SELECT across regions (inter-region distribution)
   c. Append any unassigned validators at the end
4. Truncate to nextCommitteeSize
```

### Coupled State
| Rust State | Solidity State | Coupling Invariant | Breaking Operation |
|-----------|---------------|-------------------|-------------------|
| Shuffle seed (BLS signature hash of `close_epoch` value) | N/A (computed deterministically) | All validators derive identical seed | Non-deterministic seed derivation |
| `ValidatorInfo.region` read via `getValidators(Active)` | `ValidatorInfo.region` set via `setValidatorRegion()` | Region assignment stable during shuffle | Governance calls `setValidatorRegion()` mid-epoch |
| `nextCommitteeSize` read during shuffle | `nextCommitteeSize` set via `setNextCommitteeSize()` | Size stable between shuffle and concludeEpoch | Governance changes size between shuffle and conclude |

### Adversarial Sequences
- **setValidatorRegion() between shuffle and concludeEpoch** — Rust read region data, then governance changes it. Solidity `concludeEpoch()` may validate against different region assignments than the shuffle used
- **All validators in one region** — Round-robin degenerates to sequential pick from single bucket. No geographic diversity but algorithm must still produce valid committee
- **Region assignment to 0 (unassigned) for all** — Forces fallback to plain Fisher-Yates. Verify fallback path produces identical results to non-region-aware shuffle
- **nextCommitteeSize > active validator count** — Validation is `newSize <= eligible.length` in Solidity, but what if validators exit between the size check and the shuffle?

### Audit Checklist
- [ ] Shuffle seed derivation is identical across all validators (deterministic from `close_epoch` block hash)
- [ ] Fallback path (no regions) produces same result as if all validators were in a single region
- [ ] Round-robin doesn't skip or double-count regions when bucket sizes are uneven
- [ ] Unassigned (region 0) validators are handled consistently — appended after region-diverse selection
- [ ] `nextCommitteeSize` truncation doesn't break the region distribution guarantee

## Slashing System

Slashing is executed via `applySlashes(Slash[])` as a system call during epoch boundary processing. Defined in `ConsensusRegistry.sol`.

### Execution Chain
```
applySlashes(Slash[] calldata slashes)  [onlySystemCall]
  └─ For each slash:
     └─ _consensusBurn(operator, slashAmount)
        ├─ _exit(operator)       — force transition to Exited status
        ├─ _retire(operator)     — set isRetired=true (permanent exclusion)
        ├─ _unstake(operator)    — return remaining stake minus slashAmount
        └─ confiscate slashAmount to Issuance contract balance
```

### CRITICAL ORDERING INVARIANT
`applySlashes()` MUST execute BEFORE `concludeEpoch()` in the epoch boundary sequence. The full order is:
1. `applyIncentives()` — distribute rewards
2. `applySlashes()` — slash and burn
3. `concludeEpoch()` — rotate committee

If slashes execute after concludeEpoch:
- Slashed validator may already be in the new committee
- `_exit()` would need to remove from a committee that's already been finalized

### Coupled State
| State A | State B (coupled) | Coupling Invariant | Breaking Operation |
|---------|-------------------|-------------------|-------------------|
| `balances[validator]` (post-reward) | `Issuance.balance` (confiscated funds) | Sum of all balances + Issuance.balance == total minted | Slash amount exceeds validator balance (underflow?) |
| Validator status (Active) | Committee membership | Slashed validator must be removed from current + future committees | _exit() doesn't clean future committee slots |
| `isRetired` flag | Re-activation path | Retired validators cannot re-enter via stake() + activate() | Missing retirement check in activation path |

### Adversarial Sequences
- **applySlashes + applyIncentives in wrong order** — Validator gets rewards THEN slashed. Net effect: they keep partial rewards. Correct order: rewards first, then slash (so slash can confiscate the reward too)
- **Slash amount > validator balance** — Does _consensusBurn handle underflow? Saturating subtraction or revert?
- **Slash a PendingActivation validator** — They haven't served yet. _exit() from PendingActivation status — is this a valid transition?
- **Double slash same validator in one epoch** — Second _consensusBurn on already-Exited validator. Does _exit() revert or no-op?
- **Slash during concludeEpoch re-entrancy** — _consensusBurn calls _unstake which transfers ETH. Re-entrancy guard needed?

### Audit Checklist
- [ ] `applySlashes` ordering enforced: after `applyIncentives`, before `concludeEpoch`
- [ ] `_consensusBurn` handles edge case where slashAmount >= validator's full balance
- [ ] Slashed validator is removed from all future committee arrays (not just current epoch)
- [ ] `isRetired` flag is checked in `activate()` to prevent re-entry
- [ ] No re-entrancy risk in _unstake ETH transfer within _consensusBurn
- [ ] Slash[] array cannot contain duplicate operators (or duplicates are handled safely)

## Dynamic Committee Sizing

Governance can adjust committee size via `setNextCommitteeSize(uint16)` on ConsensusRegistry.

### Mechanics
```
setNextCommitteeSize(uint16 newSize)  [onlyRole(GOVERNANCE_ROLE)]
  └─ Validation: newSize <= eligible validators count
  └─ Stored as nextCommitteeSize, takes effect at next concludeEpoch
```

### Risk Scenarios
- **Committee shrink mid-epoch** — Active validators who were in the committee may be excluded at next rotation. They don't get PendingExit status — they're simply not selected
- **Committee shrink below quorum** — If `nextCommitteeSize < 3f + 1` for the desired fault tolerance, consensus cannot make progress
- **Size change between shuffle and conclude** — Shuffle reads `nextCommitteeSize`, but governance could change it before `concludeEpoch()` validates the committee
- **Size increase beyond active validators** — Validation prevents this at `setNextCommitteeSize` time, but validators could exit between the governance call and the next epoch

### Audit Checklist
- [ ] `nextCommitteeSize` is read exactly once during shuffle and not re-read during conclude
- [ ] Minimum committee size is enforced (prevents consensus-breaking small committees)
- [ ] Size validation accounts for validators that may exit before the size takes effect
- [ ] Committee produced by shuffle matches exactly `nextCommitteeSize` (no off-by-one)

## Epoch Boundary Atomicity

The epoch boundary must execute as an atomic unit. Implemented in `block.rs` via `merge_transitions(BundleRetention::Reverts)`.

### Mechanism
```
apply_consensus_block_rewards()     → BundleState (reward transitions)
  merge into evm_state via merge_transitions(BundleRetention::Reverts)
apply_slashes()                     → BundleState (slash transitions)  
  merge into evm_state via merge_transitions(BundleRetention::Reverts)
shuffle_new_committee()             → Pure computation (no state change)
apply_closing_epoch_contract_call() → BundleState (conclude transitions)
  merge into evm_state via merge_transitions(BundleRetention::Reverts)
```

`BundleRetention::Reverts` keeps revert information so the entire epoch boundary can be rolled back if any step fails.

### Audit Checklist
- [ ] All three system calls (incentives, slashes, conclude) use `BundleRetention::Reverts`
- [ ] If any system call reverts, the entire epoch boundary is rolled back (not partially applied)
- [ ] The shuffle computation between slashes and conclude doesn't read stale state from pre-slash
- [ ] Gas metering doesn't cause an out-of-gas revert in system calls (system calls should be gas-exempt or have sufficient gas)
