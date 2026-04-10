---
name: security-eval
description: |
  Comprehensive security evaluation for telcoin-network PRs and branches.
  Orchestrates 8 parallel security agents covering consensus safety, state transitions,
  cryptographic correctness, DoS vectors, determinism, contract safety, dependency auditing,
  and deep business logic auditing via nemesis. Includes independent verification to eliminate
  false positives and root-cause remediation with actionable fixes.
  Trigger on: "security eval", "security review", "security audit PR", "is this PR safe", "pre-merge security"
---

# Security Evaluation Orchestrator

Comprehensive security evaluation for telcoin-network code changes. Spawns 8 specialized security agents in parallel, each focused on a specific attack surface, then independently verifies findings to eliminate false positives and provides root-cause remediation for confirmed vulnerabilities.

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

### Phase 3: Extract Structured Findings

After all 8 agents complete, extract each discrete finding into a canonical structure:

```
Finding ID: [agent-name]-[N]
Source Agent: [which of the 8]
Severity: CRITICAL / HIGH / MEDIUM / LOW / INFO
Title: [one-line summary]
Location: file_path:line_number
Claim: [standalone factual assertion — what is wrong]
Key Question: [the specific thing a verifier must answer]
Relevant Files: [files needed to verify]
Source: [agent name, e.g., "consensus-safety", "state-transitions"]
```

**Critical**: The `Claim` field contains ONLY the factual assertion (e.g. "function X does not validate input Y"), never the reasoning chain that led to it. This preserves independence for Phase 4 verifiers.

Assign each finding a verification tier:

| Tier | Severities | Verification Strategy |
|------|------------|----------------------|
| **Tier 1** | CRITICAL, HIGH | Verified individually — one agent per finding |
| **Tier 2** | MEDIUM | Batched 2-3 per agent, grouped by subsystem |
| **Tier 3** | LOW | Batched 3-5 per agent |
| **Skip** | INFO | No verification — observations, not vulnerability claims |

### Phase 4: Verify and Present

After extracting all structured findings in Phase 3, invoke the `findings-verifier` agent via the Agent tool to independently verify each finding, produce remediation, and present the final report.

Pass to the agent:
1. All extracted findings in canonical schema (from Phase 3)
2. The evaluation scope context (PR number, branch, or file list)
3. The full content of all changed files

The `findings-verifier` agent handles:
- Independent subagent verification (anti-confirmation bias — verifiers receive only the claim and key question, never the original agent's reasoning)
- Tiered verification (CRITICAL/HIGH individually, MEDIUM batched 2-3, LOW batched 3-5, INFO skipped)
- Root-cause remediation with decision tree (clear fix → code, multiple approaches → options, architectural → flag for human)
- Checking for similar patterns elsewhere in the codebase
- Updating the report with verification results and proposed fixes
- Presenting confirmed findings with verification stats

Do not present findings to the user before `findings-verifier` completes. Unverified findings waste time.

## Expected Agent Counts

| Phase | Agents | Notes |
|-------|--------|-------|
| 2 | 8 | Fixed — one per security domain |
| 4 (via findings-verifier) | 6-12 | Verification agents, depends on finding count and tiers |
| 4 (re-verify) | 0-3 | Low-confidence CRITICAL/HIGH verdicts only |
| 4 (remediation) | 3-8 | Confirmed findings only |
| **Total** | **17-31** | Typical ~22 |
