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
- `claude-api`: Builds and debugs applications using the Claude API and Anthropic SDKs, with prompt caching.

### Testing

- `write-e2e`: Designs end-to-end tests for the telcoin-network node covering epoch transitions, restarts, and sync.
- `write-proptest`: Generates property-based tests using proptest to verify invariants like conservation laws and BFT thresholds.
- `debug-e2e`: Diagnoses failing end-to-end tests from stdout/stderr output, including panics, timeouts, and race conditions.

### Security

- `security-eval`: Orchestrates 9 parallel security agents for a thorough audit covering consensus, state transitions, cryptography, DoS, determinism, contracts, dependencies, deep business logic (nemesis), and DREAD threat assessment.
- `review-tn`: Code review and security analysis for telcoin-network Rust code across consensus, execution, and networking layers.
- `review-tn-contracts`: Code review and security analysis for tn-contracts Solidity code, focusing on access control and invariant compliance.
- `harden-tn`: Automated hardening sweeps that find non-determinism, panic vectors, missing observability, and async-blocking hazards.
- `nemesis`: Deep-logic security audit combining first-principles questioning with state inconsistency analysis for maximum business-logic coverage.
- `threat-model`: Generates structured threat model documentation for audit preparation and attack surface analysis.

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

### Solidity Analysis

- `solidity-sentinel`: Exhaustive Solidity static analysis combining manual expert review, aderyn, and slither. Three independent tracks each verify findings before consolidation into a single report.

## Directory structure

```
claude-skills/
├── skills/          # synced skills (one subdirectory per skill)
├── agents/          # synced agents (one .md file per agent)
├── Makefile         # sync tooling
└── README.md
```
