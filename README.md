# Claude Skills

Consolidated Claude Code skills and agents synced across devices.

## Setup

```bash
git clone git@github.com:grantkee/claude-skills.git
cd claude-skills
```

## Usage

### Import skills from local machine into the repo

```bash
make import              # additive — keeps extras in repo
make import-clean        # mirror — repo matches local exactly
make import-skill SKILL=review   # single skill
```

### Install skills from the repo to local machine

```bash
make install             # additive — keeps extras locally
make clean-install       # mirror — local matches repo exactly (prompts first)
make install-skill SKILL=review  # single skill
```

### Inspect

```bash
make list    # show skills in both locations
make diff    # dry-run of what import would change
make help    # all available targets
```

## Typical workflow

**Primary device** — where you author/edit skills:

```bash
# edit skills in ~/.claude/skills/ as usual, then:
make import
git add -A && git commit -m "update skills" && git push
```

**Secondary device** — pull and install:

```bash
git pull
make install
```

## Skills

Skills are invoked with `/skill-name` and provide domain-specific capabilities.

### Development

- `tn-rust-engineer`: Rust development for the telcoin-network repo. Implements features, fixes bugs, refactors code, and adds tests.
- `add-benchmark`: Generates Criterion benchmarks for measuring latency and throughput of hot paths.

### Testing

- `write-e2e`: Designs end-to-end tests for the telcoin-network node covering epoch transitions, restarts, and sync.
- `write-proptest`: Generates property-based tests using proptest to verify invariants like conservation laws and BFT thresholds.
- `debug-e2e`: Diagnoses failing end-to-end tests from stdout/stderr output, including panics, timeouts, and race conditions.

### Security

- `security-eval`: Orchestrates 10 parallel security agents for a thorough audit covering consensus, state transitions, cryptography, DoS, determinism, contracts, dependencies, deep business logic (nemesis), DREAD threat assessment, and STRIDE threat classification.
- `review-tn`: Code review and security analysis for telcoin-network Rust code across consensus, execution, and networking layers.
- `review-tn-contracts`: Code review and security analysis for tn-contracts Solidity code, focusing on access control and invariant compliance.
- `harden-tn`: Automated hardening sweeps that find non-determinism, panic vectors, missing observability, and async-blocking hazards.
- `nemesis`: Deep-logic security audit combining first-principles questioning with state inconsistency analysis for maximum business-logic coverage.
- `threat-model`: Generates structured threat model documentation for audit preparation and attack surface analysis.
- `feynman-auditor`: Deep business logic bug finder using the Feynman technique. Language-agnostic — questions every line, ordering choice, and implicit assumption.
- `state-inconsistency-auditor`: Finds state inconsistency bugs where an operation mutates one piece of coupled state without updating its dependent counterpart.

### Documentation and writing

- `write-crate-doc`: Generates crate-level rustdoc documentation for telcoin-network crates.
- `human-writing`: Style guide that keeps prose clear and natural. Applied automatically when writing markdown, issues, PR descriptions, or documentation.
- `gh-issue`: Produces a focused GitHub issue and a PR comment summarizing all changes on a branch.
- `mermaid`: Creates mermaid diagrams (flowcharts, sequence diagrams, etc.) from natural language descriptions.

### Tooling

- `skill-creator`: Builds new skills from scratch, modifies existing ones, and runs evals to measure performance.
- `create-agent`: Interactive consultant that guides you through designing new Claude Code agent definitions.
- `update-config`: Configures Claude Code settings.json, including hooks for automated behaviors.

## Agents

Agents are autonomous workers spawned by the orchestration system. They run in isolation, can execute in parallel, and handle specific parts of a larger workflow.

### Orchestration

- `project-context`: Analyzes repo architecture and writes a shared context file that downstream agents reference. Spawned at the start of every planning session.
- `task-decomposer`: Breaks an implementation plan into focused, parallelizable units of work. Spawned after a plan is designed but before execution begins.
- `debug-orchestrator`: Triages error output, stack traces, and test failures, then routes them to the right diagnostic skill.
- `findings-verifier`: Composable verification pipeline for code review and security findings. Shared backend for review-tn, security-eval, and pr-reviewer.
- `pr-reviewer`: Standalone PR review orchestrator. Combined code review + security evaluation for any PR checkout.

### Implementation

- `tn-rust-engineer`: Writes, refactors, and patches Rust code in telcoin-network. Does not write tests (separate agents handle that).
- `write-e2e-agent`: Generates end-to-end tests after implementation is complete.
- `write-proptest-agent`: Generates property-based tests after implementation is complete.
- `write-docs-agent`: Produces crate documentation after implementation and testing are done.
- `review-agent`: Final validation step that reviews all changes before presenting results.

### Security evaluation

These agents run in parallel during a `/security-eval` pass. Each covers a specific attack surface:

- `consensus-safety`: Quorum logic, vote counting, leader election, certificate validation, Byzantine fault tolerance.
- `state-transitions`: Invariant preservation, atomicity, rollback safety, cross-component consistency.
- `crypto-correctness`: BLS signatures, ECDSA, hashing, key management, nonce handling.
- `dos-vectors`: Resource exhaustion, unbounded allocations, blocking operations in async contexts.
- `determinism-verifier`: HashMap iteration order, SystemTime usage, floating point, thread-dependent ordering.
- `contract-safety`: Solidity access control, reentrancy, stake accounting, reward distribution.
- `dependency-auditor`: New crate introductions, CVEs, feature flag changes, supply chain risk.
- `dread-evaluator`: Attacker-perspective risk assessment using the DREAD framework. Quantitative risk scoring.
- `stride-threat-model`: STRIDE threat classification (Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege).

### Solidity Analysis

- `solidity-sentinel`: Exhaustive Solidity static analysis combining manual expert review, aderyn, and slither. Three independent tracks each verify findings before consolidation into a single report.
- `solidity-invariant-auditor`: Extracts business logic from Solidity contracts and formalizes into mathematical invariant properties with Foundry test implementations.
- `solidity-gas-architect`: Analyzes Solidity contracts for gas optimization opportunities, generates refactored diffs with estimated savings, then spawns the scrutineer to validate safety.
- `solidity-change-scrutineer`: Validates proposed Solidity refactoring changes for storage layout safety, permission drift, shadowing, complexity spikes, and compiler version issues.
- `solidity-nemesis`: Adversarial exploit hypothesis agent that constructs profitable multi-step attack paths from an attacker's perspective. Chains vulnerabilities into quantified exploit hypotheses with economics and risk tables. Spawns invariant-auditor for formal property extraction, then identifies which invariants an attacker can profitably violate.

## Directory structure

```
claude-skills/
├── skills/          # synced skills (one subdirectory per skill)
├── agents/          # synced agents (one .md file per agent)
├── Makefile         # sync tooling
└── README.md
```
