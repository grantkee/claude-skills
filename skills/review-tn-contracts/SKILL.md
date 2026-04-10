# Code Review & Security Analysis for tn-contracts

Use this skill when asked to review, audit, or analyze Solidity code in the tn-contracts repository. Trigger on: "review", "audit", "security check", "invariant check", "gas optimization", "NatSpec", "artifact check", "code quality", or any request to evaluate tn-contracts code for correctness, safety, or readiness to merge. Use this skill whenever the user asks you to examine Solidity contracts for quality, security, or correctness — even if they don't explicitly say "review" or "audit".

## Project Context

This is a Foundry-based Solidity project containing core infrastructure contracts for Telcoin Network, a blockchain combining Narwhal/Bullshark consensus with EVM execution.

**Core contracts:**
- `ConsensusRegistry` (~1080 lines) — system precompile managing validator lifecycle, epoch transitions, committee selection, reward/slash application, and consensus state. Called by the protocol via system calls (`concludeEpoch`, `applyIncentives`, `applySlashes`) and by validators/governance for staking and configuration.
- `StakeManager` — ERC721-based soulbound ConsensusNFTs representing validator stake positions. Tracks stake versions, delegators, and reward accounting per validator.
- `BlsG1` — BLS12-381 G1 point operations using EIP-2537 precompiles. Used for BLS public key validation and aggregation.
- `Issuance` — Reward distribution contract. Holds epoch reward funds and processes claims. Uses low-level calls for TEL transfers.
- `SystemCallable` — Base contract enforcing system call access control (only callable by protocol at block coinbase).

**Interfaces:** `IConsensusRegistry`, `IStakeManager`, `ITELMint`

**Compiler:** solc 0.8.26, EVM Prague, optimizer 200 runs, bytecode_hash "none"

**Testing:** Foundry (forge). Fuzz: 250 runs default, 10,000 CI. Test files in `test/consensus/`.

**Artifacts:** `artifacts/` contains compiled JSON consumed by the parent repo (`../telcoin-network`) via `include_str!` in Rust code. Updated via `make update-artifacts`.

**Critical invariants:** Documented in `src/consensus/invariants.md`. These are protocol-level guarantees that must never be violated.

This context matters because these contracts govern validator lifecycle, consensus committee selection, and fund custody. A bug here can halt the network, corrupt consensus state, or lose staked funds.

Note: This skill targets the tn-contracts repo (not telcoin-network). If a `.claude/project-context.md` exists in the tn-contracts repo root, read it for additional architecture context. Otherwise, the inline context above is self-contained.

## Process

### Phase 1: Scope & Read

Determine the review scope from the user's request:

- **PR diff / branch diff**: Run `git diff master...HEAD` for the full change set. Read every changed `.sol` file in full (not just diff hunks — surrounding context catches issues the diff alone hides). Also read interfaces, parent contracts, and files that import or depend on changed files.
- **Module**: Read all `.sol` files in the module. Start with interfaces to understand the public surface, then read implementations.
- **Specific files**: Read them plus their interfaces and direct dependents if the change touches public APIs.
- **Full audit**: Read all contracts, interfaces, and test files systematically.

For every scope:
1. Read changed `.sol` files in full + their interfaces, parents, and dependents
2. Run `forge build` to confirm compilation
3. Run `git diff master...HEAD` to identify all changes (if reviewing a branch)
4. Read `src/consensus/invariants.md` for protocol invariants
5. Read `src/consensus/design.md` for design context
6. Note raw observations with `file_path:line_number` references

While reading, note concerns across these categories:

**Security**
- **Access Control** — system call restrictions (`onlySystemCall`), `onlyOwner` guards, validator-only operations, unauthorized state changes
- **Reentrancy** — external calls before state updates, low-level `.call{value}` patterns in Issuance, cross-contract callbacks
- **Arithmetic** — overflow/underflow (solc 0.8.26 has built-in checks but watch for `unchecked` blocks), division by zero, precision loss in reward calculations
- **State Manipulation** — validator status reversal (statuses must be unidirectional), committee size manipulation, epoch ring buffer corruption, unauthorized stake/reward modification
- **Cryptographic** — BLS proof verification bypass, public key uniqueness enforcement, EIP-2537 precompile return value handling
- **Economic** — reward distribution accounting (inputs = outputs), stake/reward source integrity (stake from Registry, rewards from Issuance), slash accounting
- **Consensus** — committee size bounds (never 0, never > eligible validators), epoch transition correctness, system call ordering (`concludeEpoch` must be final), Fisher-Yates shuffle integrity

**Gas & Storage**
- **Storage Layout** — slot packing efficiency, SLOAD caching in loops, cold vs warm access patterns
- **Iteration** — committee/validator iteration costs, unbounded loops, calldata vs memory for parameters
- **Events** — appropriate event emission for off-chain indexing
- **Assembly** — correctness of inline assembly in `_getValidators`, BlsG1 operations

**Code Quality**
- **NatSpec** — `@notice`, `@param`, `@return`, `@inheritdoc` completeness for public/external functions
- **Invariants** — alignment between `invariants.md` and actual code enforcement
- **Testing** — fuzz coverage, edge cases, negative testing (error paths)
- **Integration** — artifact staleness, ABI compatibility with Rust consumers

### Phase 2: Document Initial Findings

Write findings to `report.md` in the project root (or as specified by the user).

Report structure:
```
# Code Review: [scope description]
Date: [date]
Scope: [what was reviewed — branch name, PR number, file list]
Branch: [branch name if applicable]

## Summary
[1-2 sentences on overall assessment]
| # | Title | Severity | Category | Status |
|---|-------|----------|----------|--------|

## Findings

### [N]. [Title]
- **Severity**: Critical / High / Medium / Low / Informational
- **Category**: [from categories above]
- **Location**: `file_path:line_number` — `functionName()`
- **Description**: [what the code does vs. what it should do, and why the gap matters]
- **Impact**: [concrete scenario — "if a validator does X, then Y happens, resulting in Z"]
- **Evaluation**: Pending subagent analysis
```

Severity guide — calibrated for blockchain consensus infrastructure:
- **Critical** — funds at risk, consensus break/halt, committee manipulation allowing unauthorized validators, BLS verification bypass, validator status reversal enabling re-entry
- **High** — system call reverts that halt epoch transitions, incorrect reward distribution affecting all validators, committee size violations (0 or exceeding eligible validators), unauthorized stake withdrawal
- **Medium** — conditional reward calculation errors, missing boundary validation on configuration changes, gas griefing vectors against system calls, stake version accounting errors
- **Low** — suboptimal gas patterns, minor storage inefficiencies, string `require` messages vs custom errors, redundant SLOADs
- **Informational** — NatSpec gaps, style inconsistencies, dead code, test coverage suggestions, naming improvements

### Phase 3: Evaluate with 5 Parallel Subagents

Launch 5 subagents to evaluate findings and perform deep analysis. Each subagent gets specific files to read, 2-3 findings to investigate, and a structured return format. Use `subagent_type: "Explore"` for all evaluation subagents. Launch all 5 in parallel.

**Subagent 1 — Security Analysis**

Prompt template:
```
You are evaluating security findings for tn-contracts, a Foundry-based Solidity project containing core infrastructure contracts for Telcoin Network (a blockchain combining Narwhal/Bullshark consensus with EVM execution).

Read and analyze the following files for security concerns:
- src/consensus/ConsensusRegistry.sol (full — ~1080 lines)
- src/consensus/StakeManager.sol
- src/consensus/SystemCallable.sol
- src/consensus/Issuance.sol
- src/interfaces/IConsensusRegistry.sol
- src/interfaces/IStakeManager.sol
- src/consensus/invariants.md

Trace execution paths from all entry points:
1. System calls: concludeEpoch(), applyIncentives(), applySlashes() — called by protocol only
2. Validator actions: stake(), activateValidator(), beginExitValidator(), unstake(), claimRewards()
3. Owner/governance: setNextCommitteeSize(), burn(), upgradeValidatorStakeVersion()

Check specifically:
- System call access control: can any of onlySystemCall functions be called by non-system?
- Validator status unidirectionality: can any status transition go backward?
- Committee size bounds: can nextCommitteeSize become 0 or exceed eligible validators?
- Balance accounting: does stake always come from Registry and rewards from Issuance?
- Reentrancy: are there external calls before state updates, especially in Issuance low-level calls?
- BLS proof verification: can invalid or duplicate BLS keys be registered?
- Epoch ring buffer: can pointer arithmetic corrupt epoch history?
- EIP-712 replay protection: if applicable, check for cross-chain or cross-contract replay
- Slash accounting: can slashes push a validator balance negative or corrupt other validators' state?
- Burn safety: do consensus burns correctly eject from all upcoming committees without reverting?

For each concern found:
1. Trace the full code path from entry point to the issue
2. Check for existing guards (require/revert, modifiers, type constraints)
3. Search for test coverage of the behavior
4. Determine: Confirmed / False Positive / Design Decision / Partially Valid
5. Rate severity: Critical / High / Medium / Low / Informational
6. Propose concrete Solidity fix if Confirmed or Partially Valid

Also investigate these specific findings from Phase 2:
[INSERT 2-3 FINDINGS HERE]

Return structured results with file_path:line_number references for every finding.
```

**Subagent 2 — Gas & Storage Optimization**

Prompt template:
```
You are analyzing gas and storage efficiency for tn-contracts, a Foundry-based Solidity project.

Run the following commands:
- forge inspect ConsensusRegistry storage-layout
- forge inspect StakeManager storage-layout

Read and analyze:
- src/consensus/ConsensusRegistry.sol
- src/consensus/StakeManager.sol
- src/consensus/BlsG1.sol

Check specifically:
- Storage slot packing: are struct fields and state variables ordered to minimize slots?
- SLOAD caching: are storage reads inside loops cached in memory variables?
- Committee iteration: what is the gas cost of iterating the full committee/validator set?
- calldata vs memory: are function parameters using the cheaper option where possible?
- Event emission: are events emitted for all state changes needed by off-chain indexers?
- Assembly correctness: verify inline assembly in _getValidators() and BlsG1 operations
  - Check memory safety, correct ABI encoding, proper return data handling
  - Verify EIP-2537 precompile call conventions (gas, input format, return values)
- Unchecked blocks: are they safe (can the arithmetic actually overflow)?
- Mapping vs array tradeoffs for validator storage

For each optimization found:
- Estimate gas savings (approximate SLOAD/SSTORE costs: cold=2100, warm=100, store=5000/20000)
- Rate as Low (minor) or Medium (measurable impact on system calls)
- Propose concrete Solidity fix
- Flag if the optimization would change storage layout (breaking for proxied contracts)

Also investigate these specific findings from Phase 2:
[INSERT 2-3 FINDINGS HERE]

Return structured results with file_path:line_number references.
```

**Subagent 3 — Documentation & Invariants**

Prompt template:
```
You are reviewing documentation and invariant enforcement for tn-contracts, a Foundry-based Solidity project containing core infrastructure contracts for Telcoin Network.

Read:
- src/interfaces/IConsensusRegistry.sol
- src/interfaces/IStakeManager.sol
- src/consensus/ConsensusRegistry.sol
- src/consensus/StakeManager.sol
- src/consensus/Issuance.sol
- src/consensus/invariants.md
- src/consensus/design.md

Check NatSpec completeness:
- Every public/external function must have @notice, @param (for each parameter), @return (for each return value)
- Interface functions should define the NatSpec; implementations should use @inheritdoc
- Check for stale NatSpec that doesn't match current function signatures or behavior
- Flag functions with no NatSpec at all

Check invariants alignment:
- For EACH invariant listed in invariants.md:
  1. Identify which code enforces it (specific require/revert, modifier, or logic)
  2. Identify which test verifies it
  3. Flag if enforcement is missing or incomplete
  4. Flag if test coverage is missing
- Check for code-level invariants NOT documented in invariants.md (missing documentation)
- Check if design.md is consistent with current implementation

Return:
- NatSpec coverage percentage (functions with complete NatSpec / total public+external functions)
- Table of invariants with enforcement status and test coverage
- List of undocumented invariants found in code
- List of stale or incorrect NatSpec
- List of design.md inconsistencies
```

**Subagent 4 — Testing & Coverage**

Prompt template:
```
You are reviewing test quality and coverage for tn-contracts, a Foundry-based Solidity project.

Run:
- forge test (verify all tests pass)
- forge coverage (get coverage metrics)

Read:
- test/consensus/ConsensusRegistryTest.t.sol
- test/consensus/ConsensusRegistryTestFuzz.t.sol
- test/consensus/ConsensusRegistryTestUtils.sol
- Any other test files in test/

Check:
- Do all tests pass? Report any failures with full output.
- What is the line/branch/function coverage for each contract?
- Fuzz tests: do they exist for all state-changing functions? Are fuzz bounds realistic?
- Edge cases: are boundary conditions tested (0, 1, max values, empty arrays)?
- Negative testing: is every custom error tested? Is every revert path exercised?
- State transition testing: are all valid state transitions tested? Are invalid transitions tested (should revert)?
- System call testing: are concludeEpoch, applyIncentives, applySlashes tested with various committee sizes and validator states?
- Integration patterns: do tests cover multi-epoch scenarios, concurrent validator operations?

For gaps found:
- Rate importance: High (untested critical path), Medium (untested edge case), Low (minor gap)
- Suggest specific test cases with function signatures

Return:
- Test pass/fail status
- Coverage percentages per contract
- Table of coverage gaps by importance
- Suggested test cases for critical gaps
```

**Subagent 5 — Integration & Artifact Compatibility**

Prompt template:
```
You are checking integration compatibility for tn-contracts, a Foundry-based Solidity project whose compiled artifacts are consumed by a parent Rust repo (telcoin-network).

Read:
- All files in artifacts/ directory (check JSON structure)
- Makefile (verify update-artifacts completeness)
- src/consensus/ConsensusRegistry.sol (view functions section)

Check artifact staleness:
- Compare source file modification times vs artifact modification times
- Flag if any artifact is older than its source (needs `make update-artifacts`)
- Verify Makefile copies all necessary artifacts

Check Rust consumer compatibility (read these files in the parent repo if accessible):
- ../telcoin-network/crates/config/src/genesis.rs
- Any files in telcoin-network that reference tn-contracts artifacts (search for include_str! with artifact names)
- Flag ABI breaking changes: renamed functions, changed parameter types/order, removed functions, changed event signatures

Check view function coverage:
- Are there view functions for all important state? (validators, committees, epochs, stake positions, system configuration)
- Can off-chain consumers reconstruct full system state from view functions alone?
- Are view functions gas-efficient for large validator sets?

Check Makefile completeness:
- Does it copy all contract artifacts that the parent repo needs?
- Are there new contracts whose artifacts should be added?

Return:
- Artifact staleness status (which need updating)
- List of ABI breaking changes (if any)
- View function coverage assessment
- Makefile completeness check
- Whether `make update-artifacts` is needed
```

### Phase 4: Update Report

After all subagents return, update `report.md`:

1. Update the summary table with final status and actual severity from subagent analysis
2. Replace "Pending subagent analysis" with each subagent's detailed analysis
3. For Confirmed findings, include the proposed Solidity fix with code
4. For False Positives, explain why — this documents design decisions and prevents re-raising
5. Remove findings proven completely invalid
6. Reorder remaining findings by severity (Critical first)
7. Add the following sections from subagent results:
   - **Invariants Check** — table of invariants with enforcement and test status
   - **Artifact Compatibility** — staleness, ABI changes, Makefile completeness
   - **Test Coverage Summary** — pass/fail, coverage percentages, critical gaps
   - **Gas Optimization Opportunities** — confirmed optimizations with estimated savings

### Phase 5: Present Results

Summarize directly in the conversation:
- Total findings vs. confirmed count by severity
- Table of confirmed findings with severity and one-line description
- Call out any Critical or High findings explicitly with brief explanation
- Note if `make update-artifacts` is needed
- Note if `invariants.md` needs updates
- Report test pass/fail status and coverage percentage
- List gas optimization opportunities with estimated savings

Keep this concise — the full details are in `report.md`.

## Rules

- Every finding goes through subagent evaluation before being presented as confirmed. Unverified findings waste time.
- Read code before commenting on it. Speculation produces false positives.
- Include `file_path:line_number` and function name for every finding.
- Propose concrete Solidity fixes, not just problems. A finding without a solution is half-finished.
- Group subagent work by domain (security, gas, docs, testing, integration) for focused analysis.
- Calibrate severity honestly. A NatSpec gap is Informational, not Medium. A missing require in an owner-only function is not Critical.
- System call paths that could revert = minimum High severity. These halt epoch transitions.
- Validator status reversal = Critical. Unidirectionality is a core protocol invariant.
- Check assembly blocks in `_getValidators` and `BlsG1` — manual memory management is error-prone.
- Check low-level call return values in Issuance `.call{value}` patterns — unchecked returns lose funds silently.
- After interface changes, always check if `make update-artifacts` is needed.
- Check compiler version (0.8.26) against known solc bugs for that version.
- For reward/slash calculations, verify complete accounting: inputs must equal outputs.
- Consensus burns must not cause reverts in subsequent system calls (`concludeEpoch`, `applyIncentives`, `applySlashes`).
- `unchecked` blocks are a red flag — verify the arithmetic genuinely cannot overflow/underflow.
- Storage layout changes in a proxied contract are breaking — flag these as Critical.
