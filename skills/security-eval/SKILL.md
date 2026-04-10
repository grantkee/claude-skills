---
name: security-eval
description: |
  Comprehensive security evaluation for telcoin-network PRs and branches.
  Orchestrates 8 parallel security agents covering consensus safety, state transitions,
  cryptographic correctness, DoS vectors, determinism, contract safety, dependency auditing,
  and deep business logic auditing via nemesis.
  Trigger on: "security eval", "security review", "security audit PR", "is this PR safe", "pre-merge security"
---

# Security Evaluation Orchestrator

Comprehensive security evaluation for telcoin-network code changes. Spawns 8 specialized security agents in parallel, each focused on a specific attack surface, then synthesizes findings into a unified report.

## Severity Scale (Blockchain-Calibrated)

| Level        | Definition                                              | Examples                                                                                    |
| ------------ | ------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| **CRITICAL** | Consensus break, fund loss, chain halt, or forked state | Quorum miscalculation, determinism violation in state transition, unprotected fund transfer |
| **HIGH**     | Security degradation or data corruption                 | Missing signature verification, unbounded allocation, unsafe key handling                   |
| **MEDIUM**   | Defense-in-depth gap or reliability issue               | Missing input validation on network boundary, inadequate error handling in consensus path   |
| **LOW**      | Code quality issue with security implications           | Inconsistent error types, missing logging in security-relevant paths                        |
| **INFO**     | Observation or hardening suggestion                     | Style inconsistency, documentation gap in security-sensitive code                           |

## Process

### Phase 1: Scope Identification

Determine what code to evaluate:

- If given a PR number: run `git diff main...HEAD` or `gh pr diff <number>`
- If given a branch: run `git diff main...<branch>`
- If given specific files: use those directly
- Read all changed files in full plus their direct dependents

### Phase 2: Spawn Security Agents

Spawn ALL 8 agents in parallel using the Agent tool. Each agent receives:

1. The list of changed files and their diffs
2. The full content of changed files
3. Instructions to read `.claude/project-context.md` for architecture context

The 8 agents and their focus areas:

| Agent                  | Focus                                                                | Skills to Invoke           |
| ---------------------- | -------------------------------------------------------------------- | -------------------------- |
| `consensus-safety`     | BFT assumptions, quorum logic, vote counting, leader election        | harden-tn + threat-model   |
| `state-transitions`    | Invariant violations, partial state updates, rollback safety         | nemesis + review-tn        |
| `crypto-correctness`   | Signatures, hashing, key management, nonce handling                  | review-tn (crypto paths)   |
| `dos-vectors`          | Resource exhaustion, unbounded allocations, amplification            | harden-tn (blocking audit) |
| `determinism-verifier` | HashMap iteration, SystemTime, thread-dependent ordering, randomness | harden-tn (determinism)    |
| `contract-safety`      | Access control, reentrancy, accounting, upgrade safety               | review-tn-contracts        |
| `dependency-auditor`   | New crates, CVE exposure, supply chain, feature flags                | Cargo.toml diff analysis   |
| `nemesis-auditor`      | Deep iterative business logic + state inconsistency cross-analysis   | nemesis                    |

### Phase 3: Synthesize Report

After all 8 agents complete, compile their findings into a unified report:

```
# Security Evaluation Report

## Executive Summary
- **Overall Risk**: CRITICAL / HIGH / MEDIUM / LOW / CLEAN
- **Agents Run**: 8/8
- **Total Findings**: N (X critical, Y high, Z medium)
- **Recommendation**: BLOCK / APPROVE_WITH_FIXES / APPROVE

## Critical & High Findings
[List each finding with: agent source, severity, file:line, description, remediation]

## Medium & Low Findings
[Grouped by agent]

## Agent Reports

### consensus-safety
[Full agent report]

### state-transitions
[Full agent report]

### crypto-correctness
[Full agent report]

### dos-vectors
[Full agent report]

### determinism-verifier
[Full agent report]

### contract-safety
[Full agent report]

### dependency-auditor
[Full agent report]

### nemesis-auditor
[Full agent report]

## Methodology Notes
- All 8 agents ran independently with no shared state
- Each agent used its designated skills for domain-specific analysis
- Severity calibrated for blockchain: consensus breaks and fund loss are CRITICAL
```

### Phase 4: Present Results

Present the unified report. If any CRITICAL findings exist:

- List each critical finding with specific file and line
- Provide concrete remediation steps

If no critical findings:

- State overall risk level
- List high/medium findings that should be addressed
- Provide approval recommendation
