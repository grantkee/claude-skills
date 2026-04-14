# Claude Skills

Consolidated Claude Code skills (24) and agents (41) synced across devices.

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
- `tn-add-benchmark`: Generates Criterion benchmarks for measuring latency and throughput of hot paths.

### Testing

- `tn-write-e2e`: Designs end-to-end tests for the telcoin-network node covering epoch transitions, restarts, and sync.
- `tn-write-proptest`: Generates property-based tests using proptest to verify invariants like conservation laws and BFT thresholds.
- `tn-debug-e2e`: Diagnoses failing end-to-end tests from stdout/stderr output, including panics, timeouts, and race conditions.

### Security

- `tn-security-eval`: Orchestrates 10 parallel security agents for a thorough audit covering consensus, state transitions, cryptography, DoS, determinism, contracts, dependencies, deep business logic (nemesis), DREAD threat assessment, and STRIDE threat classification.
- `tn-review`: Code review and security analysis for telcoin-network Rust code across consensus, execution, and networking layers.
- `tn-review-contracts`: Code review and security analysis for tn-contracts Solidity code, focusing on access control and invariant compliance.
- `tn-harden`: Automated hardening sweeps that find non-determinism, panic vectors, missing observability, and async-blocking hazards.
- `tn-threat-model`: Generates structured threat model documentation for audit preparation and attack surface analysis.
- `feynman-auditor`: Deep business logic bug finder using the Feynman technique. Language-agnostic — questions every line, ordering choice, and implicit assumption.
- `state-inconsistency-auditor`: Finds state inconsistency bugs where an operation mutates one piece of coupled state without updating its dependent counterpart.
- `nemesis-scan`: Deep combined Feynman + State Inconsistency audit with dynamic domain discovery across 8 phases. Language-agnostic. Spawns nemesis-orchestrator.
- `tn-nemesis-scan`: Telcoin-network variant of nemesis-scan with protocol-specific domain patterns.
- `nemesis-og`: Original nemesis — iterative Feynman + State Inconsistency feedback loop until convergence.
- `solidity-security-scan`: One-command orchestrator spawning 3-4 Solidity agents in parallel (sentinel, nemesis, gas-architect, optionally deploy-auditor).

### Documentation and writing

- `doc-writer`: Sequential editing pipeline for technical documentation. Decomposes prose rules into focused single-pass agents.
- `tn-write-crate-doc`: Generates crate-level rustdoc documentation for telcoin-network crates.
- `human-writing`: Style guide that keeps prose clear and natural. Applied automatically when writing markdown, issues, PR descriptions, or documentation.
- `gh-issue`: Produces a focused GitHub issue and a PR comment summarizing all changes on a branch.
- `mermaid`: Creates mermaid diagrams (flowcharts, sequence diagrams, etc.) from natural language descriptions.

### Tooling

- `skill-creator`: Builds new skills from scratch, modifies existing ones, and runs evals to measure performance.
- `create-agent`: Interactive consultant that guides you through designing new Claude Code agent definitions.

### Internal

- `tn-rust-skills`: Reference skill containing telcoin-network Rust coding conventions and project context. Loaded by tn-* agents automatically — not user-invocable.

## Agents

Agents are autonomous workers spawned by the orchestration system. They run in isolation, can execute in parallel, and handle specific parts of a larger workflow.

### Orchestration

- `project-context`: Analyzes repo architecture and writes a shared context file that downstream agents reference. Spawned at the start of every planning session.
- `task-decomposer`: Breaks an implementation plan into focused, parallelizable units of work. Spawned after a plan is designed but before execution begins.
- `tn-debug-orchestrator`: Triages error output, stack traces, and test failures, then routes them to the right diagnostic skill.
- `findings-verifier`: Composable verification pipeline for code review and security findings. Shared backend for tn-review, tn-security-eval, and tn-pr-reviewer.
- `tn-pr-reviewer`: Standalone PR review orchestrator. Combined code review + security evaluation for any PR checkout.
- `format-output`: Applies file-specific formatting rules to prose output. Spawned by the human-writing skill after writing or editing prose files.

### Implementation

- `tn-rust-engineer`: Writes, refactors, and patches Rust code in telcoin-network. Does not write tests (separate agents handle that).
- `tn-write-e2e-agent`: Generates end-to-end tests after implementation is complete.
- `tn-write-proptest-agent`: Generates property-based tests after implementation is complete.
- `tn-write-docs-agent`: Produces crate documentation after implementation and testing are done.
- `tn-review-agent`: Final validation step that reviews all changes before presenting results.

### tn-rust-engineer subagents

Internal agents spawned by the `tn-rust-engineer` skill pipeline. Not spawned independently.

- `tn-task-analyzer`: Phase 1 — analyzes task scope, affected layers, and existing patterns.
- `tn-impl-planner`: Phase 2 — plans implementation strategy with crate ordering and type placement.
- `tn-verifier`: Phase 4 — verifies correctness via cargo check, fmt, clippy, and nextest scoped to changed crates.
- `tn-debugger`: Classifies verification failures and routes to debug-orchestrator for diagnosis.

### Security evaluation

These agents run in parallel during a `/tn-security-eval` pass. Each covers a specific attack surface:

- `tn-consensus-safety`: Quorum logic, vote counting, leader election, certificate validation, Byzantine fault tolerance.
- `tn-state-transitions`: Invariant preservation, atomicity, rollback safety, cross-component consistency.
- `tn-crypto-correctness`: BLS signatures, ECDSA, hashing, key management, nonce handling.
- `tn-dos-vectors`: Resource exhaustion, unbounded allocations, blocking operations in async contexts.
- `tn-determinism-verifier`: HashMap iteration order, SystemTime usage, floating point, thread-dependent ordering.
- `tn-contract-safety`: Solidity access control, reentrancy, stake accounting, reward distribution.
- `tn-dependency-auditor`: New crate introductions, CVEs, feature flag changes, supply chain risk.
- `tn-dread-evaluator`: Attacker-perspective risk assessment using the DREAD framework. Quantitative risk scoring.
- `tn-stride-threat-model`: STRIDE threat classification (Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege).

### Nemesis orchestration

These agents form the `/nemesis-scan` pipeline. Spawned by `nemesis-orchestrator` — not used independently.

- `nemesis-orchestrator`: Coordinates the full nemesis workflow across all phases, from domain discovery through reporting.
- `nemesis-strategy`: Phase -1a — produces a structured research plan with 3-8 topics for domain discovery.
- `nemesis-researcher`: Phase -1b — investigates a single research topic and produces domain-pattern fragments.
- `nemesis-recon`: Phase 0 — attacker reconnaissance identifying value stores, complex paths, and coupled value hypotheses.
- `nemesis-mapper`: Phase 1 — builds the Function-State Matrix, Coupled State Dependency Map, and unified Nemesis Map.
- `nemesis-feynman`: Phase 2 — full Feynman interrogation using 7 question categories on every function in priority order.
- `nemesis-state-check`: Phase 3 — state inconsistency analysis enriched by Feynman findings.
- `nemesis-verifier`: Phase 6 — verifies CRITICAL, HIGH, and MEDIUM findings through deep code tracing.
- `nemesis-journey`: Phase 5 — traces multi-transaction adversarial sequences that chain state gaps with ordering concerns.
- `nemesis-reporter`: Phase 7 — generates the final verified report from all phase artifacts.

### Solidity analysis

- `solidity-sentinel`: Exhaustive Solidity static analysis combining manual expert review, aderyn, and slither. Three independent tracks each verify findings before consolidation into a single report.
- `solidity-invariant-auditor`: Extracts business logic from Solidity contracts and formalizes into mathematical invariant properties with Foundry test implementations.
- `solidity-gas-architect`: Analyzes Solidity contracts for gas optimization opportunities, generates refactored diffs with estimated savings, then spawns the scrutineer to validate safety.
- `tn-solidity-change-scrutineer`: Validates proposed Solidity refactoring changes for storage layout safety, permission drift, shadowing, complexity spikes, and compiler version issues.
- `solidity-nemesis`: Adversarial exploit hypothesis agent that constructs profitable multi-step attack paths from an attacker's perspective. Chains vulnerabilities into quantified exploit hypotheses with economics and risk tables. Spawns invariant-auditor for formal property extraction, then identifies which invariants an attacker can profitably violate.
- `tn-foundry-invariant-architect`: Receives formalized invariant properties from solidity-invariant-auditor and produces compilable Foundry invariant tests with Handler contracts and ghost variables.
- `tn-solidity-deploy-auditor`: Evaluates Foundry deployment scripts for security vulnerabilities — transaction ordering, key management, proxy initialization atomicity, and front-running risks.

## Directory structure

```
claude-extensions-personal/
├── skills/          # 24 synced skills
├── agents/          # 41 synced agents
├── .claude/         # Claude Code config & project context
├── Makefile         # sync tooling
├── CLAUDE.md        # workflow orchestration rules
├── LICENSE          # MIT
└── README.md
```
