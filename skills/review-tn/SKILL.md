# Code Review & Security Analysis Skill

Use this skill when asked to review code, audit files, analyze PRs, or perform security analysis. Trigger on: "review", "audit", "analyze", "code review", "PR review", "security check", "look at this code", "check this module", "what do you think of this". Use this skill whenever the user asks you to examine code for quality, safety, or correctness — even if they don't explicitly say "review" or "audit".

## Project Context

This is a Rust blockchain node (telcoin-network) combining a Narwhal/Bullshark consensus layer with EVM execution via Reth. The codebase uses tokio for async, gRPC (Tonic) for internal communication, BLS signatures (blst), and Alloy/Reth for Ethereum primitives.

**Crate structure (~18 crates):**
- **Consensus** — consensus/primary, consensus/worker, consensus/executor (Narwhal/Bullshark DAG-based consensus)
- **Execution** — batch-builder, batch-validator, tn-reth, engine (EVM execution pipeline)
- **Networking** — network-libp2p, state-sync (peer discovery, block/state propagation)
- **Infrastructure** — config, types, tn-utils, tn-rpc, storage (shared primitives, configuration, persistence)
- **Integration** — node, CLI, e2e-tests (node assembly and end-to-end testing)

**Workspace lint configuration** (from workspace Cargo.toml):
- `missing_docs = "warn"`, `rustdoc::all = "warn"`, `unused_must_use = "deny"`

**Test infrastructure:**
- `cargo nextest` for unit/integration tests, `make public-tests` for the full public test suite, `make pr` for the CI-equivalent local check
- E2E tests in `crates/e2e-tests/` run with `--run-ignored`

**CI pipeline:** fmt (nightly toolchain), clippy, nextest — PRs must pass all three.

This context matters because the review categories and severity assessments below are tuned for a system where correctness equals safety — consensus bugs can halt the network, EVM mismatches can lose funds, and concurrency bugs in async networking can corrupt state.

## Process

### Phase 1: Scope & Read

Determine the review scope from the user's request:

- **PR diff**: Run `git diff` for the relevant range. Read every changed file in full (not just the diff hunks — surrounding context catches issues the diff alone hides). Also read files that import or are imported by changed files when the change touches a public interface.
- **Module/crate**: Read all `.rs` files in the crate. Start with `lib.rs` or `main.rs` to understand the module's public surface, then read internal modules. For large crates (20+ files), read `lib.rs` first to understand structure, then prioritize files touching consensus, state, crypto, or networking.
- **Specific files**: Read them plus their direct dependents if the change touches public APIs.

**Subagent strategy for Phase 1 reading** — scale context windows to scope size:
- **1-2 files**: Read directly in the main context (no subagents needed).
- **Single crate**: Launch 1-2 Explore subagents — one for source files, one for tests and downstream dependents.
- **Multiple crates or full audit**: Launch up to 3 Explore subagents, each assigned a domain:
  - **Consensus & Networking** — consensus/primary, consensus/worker, consensus/executor, network-libp2p, state-sync
  - **Execution & Storage** — batch-builder, batch-validator, tn-reth, engine, storage
  - **Infrastructure & Integration** — config, types, tn-utils, tn-rpc, node, CLI

Each subagent reads source files, notes concerns with `file_path:line_number`, and returns raw observations (not findings — classification happens in Phase 2). Use `subagent_type: "Explore"` and launch all reading subagents in parallel.

While reading, note the file path, line numbers, and any concerns across these categories:

**Rust & Systems**
- **Memory & Safety** — `unsafe` blocks without safety comments, raw pointer manipulation, transmute, missing bounds checks, buffer handling, use-after-free patterns
- **Concurrency** — data races, deadlock potential (lock ordering), `Send`/`Sync` bound issues, missing or incorrect use of `Arc`/`Mutex`/`RwLock`, unbounded channel/queue growth, task cancellation safety (what happens when a tokio task is dropped mid-await?)
- **Error Handling** — `unwrap()`/`expect()` on fallible operations in non-test code (these panic and crash the node), `_` catch-all in match arms that silently swallow new variants, error chains that lose context via `.map_err(|_| ...)`

**Consensus & Blockchain**
- **Determinism** — any operation whose output could vary across validators breaks consensus. Watch for: HashMap iteration order, floating point, system time, thread-dependent ordering, randomness without deterministic seeding
- **Consensus Safety** — incorrect quorum calculations, missing signature verification on messages, accepting messages from wrong rounds/epochs, equivocation handling, certificate validation gaps
- **State & Funds** — EVM state transitions that don't match Ethereum semantics, incorrect gas accounting, missing balance checks, storage writes without corresponding reads for validation, batch execution ordering assumptions
- **Fork Safety** — code that behaves differently at different block heights without explicit fork-gating, upgrade paths that could split the network

**General**
- **Security** — access control bypasses, unvalidated external input (network messages, RPC params, CLI args), cryptographic misuse (nonce reuse, weak randomness, missing constant-time comparison), resource exhaustion vectors (unbounded allocations from untrusted input)
- **Bugs** — logic errors, off-by-one, incorrect error propagation, silent failures, type confusion between similar newtypes
- **Architecture** — layering violations (consensus code reaching into execution internals or vice versa), missing abstraction boundaries, god objects, inconsistent patterns across similar code
- **Optimization** — unnecessary allocations in hot paths, redundant computation, runtime work that could be compile-time (`const fn`, type-level computation), inefficient data structures for the access pattern

**Documentation & Comments**
- **Doc comments** — public items missing `///` docs (workspace lint: `missing_docs = "warn"`), module-level `//!` docs missing in `lib.rs`
- **Stale comments** — comments describing behavior the code no longer exhibits, TODO/FIXME items referencing resolved issues
- **Rustdoc** — broken intra-doc links, missing examples on complex public APIs (workspace lint: `rustdoc::all = "warn"`)

**Test Coverage**
- **Unit tests** — public functions without corresponding `#[cfg(test)]` coverage in the same file
- **Integration tests** — changes to public crate APIs without corresponding tests in `tests/it/`
- **E2E coverage** — consensus/execution changes without e2e test updates in `crates/e2e-tests/`
- **Test quality** — tests that only check the happy path without error/edge cases, missing `#[tokio::test]` for async code

### Phase 2: Document Findings

Write findings to `report.md` in the project root (or as specified by the user).

Report structure:
```
# Code Review: [scope description]
Date: [date]
Scope: [what was reviewed — PR number, crate name, or file list]

## Summary
[1-2 sentences on overall assessment]
| # | Title | Severity | Category | Status |
|---|-------|----------|----------|--------|

## Findings

### [N]. [Title]
- **Severity**: Critical / High / Medium / Low / Informational
- **Category**: [from list above]
- **Location**: `file_path:line_number`
- **Description**: [what the code does vs. what it should do, and why the gap matters]
- **Impact**: [concrete scenario — "if a validator sends X, then Y happens, resulting in Z"]
- **Evaluation**: Pending subagent analysis
```

Severity guide — calibrated for a blockchain node:
- **Critical** — funds at risk, consensus break/halt, remote code execution, state corruption that persists across restarts
- **High** — denial of service against the node, privilege escalation, incorrect state transitions that are recoverable, panics in production paths that crash the node
- **Medium** — silent failures affecting correctness that don't immediately break consensus, missing validation at system boundaries (RPC, network messages), economic impact under specific conditions
- **Low** — suboptimal patterns, minor inefficiencies, weak diagnostics, `unwrap()` in paths that are practically safe but not provably so
- **Informational** — style, naming, dead code, compile-time improvements, idiomatic Rust suggestions

### Phase 3: Evaluate with 4 Parallel Subagents

Launch 4 domain-specific subagents to verify findings and perform deep analysis. This step exists because initial review catches surface patterns, but many turn out to be false positives once you trace the full code path. Use `subagent_type: "Explore"` for all subagents. Launch all 4 in parallel.

Assign each subagent 2-3 findings from Phase 2 that fall within its domain.

**Subagent 1 — Security & Concurrency**

```
You are evaluating security and concurrency findings for telcoin-network, a Rust blockchain node combining Narwhal/Bullshark consensus with EVM execution via Reth.

For each concern below, read the source files, trace the code path from entry points to the flagged location, and determine whether the concern is valid.

Investigate specifically:
- unsafe blocks: is the safety invariant documented and actually upheld?
- Concurrency: lock ordering (deadlock potential), Arc/Mutex usage, unbounded channel growth, tokio task cancellation safety (what happens when dropped mid-await?)
- Crypto: BLS signature verification completeness, nonce reuse, constant-time comparison for secrets
- Resource exhaustion: unbounded allocations from untrusted network messages or RPC params

Pay special attention to:
- Rust compiler guarantees that may make the concern impossible (borrow checker, exhaustive matches, type safety)
- Upstream validation that prevents problematic input from reaching this code
- Whether `debug_assert!` is the only guard (stripped in release builds — not a production guard)

## Concern N: [Title]
**Location:** [file:line]
**Claim:** [what the initial review found]
**Key question:** [specific thing to verify]

Investigate:
1. Read [specific files]
2. Trace the code path from entry point (RPC handler, network message handler, consensus round) to the flagged location
3. Check for existing guards, tests, or type-level validation
4. Determine: Confirmed / False Positive / Design Decision / Partially Valid

Return for each concern:
- **Status:** Confirmed / False Positive / Design Decision / Partially Valid
- **Actual Severity:** Critical / High / Medium / Low / Informational
- **Analysis:** [trace the path, cite guards or lack thereof, with file_path:line_number]
- **Proposed Fix:** [concrete Rust code if Confirmed or Partially Valid]
```

**Subagent 2 — Consensus & Determinism**

```
You are evaluating consensus and determinism findings for telcoin-network, a Rust blockchain node using Narwhal/Bullshark DAG-based consensus with EVM execution.

For each concern, verify whether the behavior is deterministic across all validators given the same input.

Investigate specifically:
- Determinism violations: HashMap iteration order in consensus paths, floating point, system time, thread-dependent ordering, randomness without deterministic seeding
- Quorum logic: incorrect quorum threshold calculations, missing signature verification on messages, accepting messages from wrong rounds/epochs
- State transitions: EVM state transitions that don't match Ethereum semantics, incorrect gas accounting, batch execution ordering assumptions
- Fork safety: code that behaves differently at different block heights without explicit fork-gating
- Epoch handling: epoch boundary transitions, committee rotation correctness

Key principle: if two honest validators could produce different results from the same input, that's at minimum High severity.

## Concern N: [Title]
**Location:** [file:line]
**Claim:** [what the initial review found]
**Key question:** [specific thing to verify]

Investigate:
1. Read [specific files]
2. Trace the consensus path end-to-end
3. Check for existing guards, tests, or type-level validation
4. Determine: Confirmed / False Positive / Design Decision / Partially Valid

Return for each concern:
- **Status:** Confirmed / False Positive / Design Decision / Partially Valid
- **Actual Severity:** Critical / High / Medium / Low / Informational
- **Analysis:** [trace the path, cite guards or lack thereof, with file_path:line_number]
- **Proposed Fix:** [concrete Rust code if Confirmed or Partially Valid]
```

**Subagent 3 — Documentation & Test Coverage**

```
You are evaluating documentation and test coverage for telcoin-network, a Rust blockchain node.

Workspace lint config: missing_docs = "warn", rustdoc::all = "warn", unused_must_use = "deny".

Check documentation:
- Public items missing /// doc comments (especially in lib.rs re-exports and public trait methods)
- Module-level //! docs missing in lib.rs files
- Stale comments describing behavior the code no longer exhibits
- TODO/FIXME items referencing resolved issues
- Broken intra-doc links

Check test coverage:
- Public functions without corresponding #[cfg(test)] coverage
- Changes to public crate APIs without integration tests in tests/it/
- Consensus/execution changes without e2e test updates in crates/e2e-tests/
- Tests that only check happy paths without error/edge cases
- Missing #[tokio::test] for async test functions

If the review scope warrants it, run `make public-tests` to verify the test suite passes.

Also investigate these specific findings from Phase 2:
[INSERT 2-3 FINDINGS HERE]

Return:
- Documentation gaps with file_path:line_number references
- Test coverage gaps rated by importance (High = untested critical path, Medium = untested edge case, Low = minor gap)
- Test pass/fail status (if tests were run)
- Suggested test cases for critical gaps
```

**Subagent 4 — Architecture & Integration**

```
You are evaluating architecture and integration findings for telcoin-network, a Rust blockchain node with ~18 crates spanning consensus, execution, networking, and infrastructure.

Investigate specifically:
- Layering violations: consensus code reaching into execution internals or vice versa, networking code making assumptions about consensus state
- Cross-crate API compatibility: breaking changes to public crate APIs without updating dependents, version-incompatible type usage
- Error handling patterns: unwrap()/expect() in non-test code (panics crash the node), _ catch-all in match arms swallowing new variants, error chains losing context via .map_err(|_| ...)
- Optimization opportunities: unnecessary allocations in hot paths (consensus message handling, block execution), redundant computation, runtime work that could be const fn

## Concern N: [Title]
**Location:** [file:line]
**Claim:** [what the initial review found]
**Key question:** [specific thing to verify]

Investigate:
1. Read [specific files]
2. Check cross-crate usage and dependency direction
3. Verify error handling patterns against the crate's public API guarantees
4. Determine: Confirmed / False Positive / Design Decision / Partially Valid

Return for each concern:
- **Status:** Confirmed / False Positive / Design Decision / Partially Valid
- **Actual Severity:** Critical / High / Medium / Low / Informational
- **Analysis:** [trace the path, cite guards or lack thereof, with file_path:line_number]
- **Proposed Fix:** [concrete Rust code if Confirmed or Partially Valid]
```

### Phase 4: Update Report

After all subagents return, update `report.md`:

1. Update the summary table with final status and actual severity
2. Replace "Pending subagent analysis" with the subagent's analysis
3. For Confirmed findings, include the proposed fix with code
4. For False Positives, explain why — this documents design decisions and prevents the same concern from being re-raised
5. Remove findings that were proven completely invalid (don't clutter the report)
6. Reorder remaining findings by severity (Critical first)
7. Add the following sections from subagent results:
   - **Test Coverage Summary** — pass/fail status, notable gaps by importance
   - **Documentation Gaps** — missing doc comments, stale comments, broken rustdoc links

### Phase 5: Present Results

Summarize directly in the conversation:
- Total findings vs. confirmed count
- Table of confirmed findings with severity and one-line description
- Call out any Critical or High findings explicitly with a brief explanation
- Test pass/fail status and notable coverage gaps
- Documentation completeness note (if significant gaps found)
- Mention notable False Positives only if they reveal non-obvious design decisions worth understanding

Keep this concise — the full details are in `report.md`.

## Rules

- Every finding goes through subagent evaluation before being presented as confirmed. Unverified findings waste time.
- Read code before commenting on it. Speculation produces false positives.
- Include `file_path:line_number` references for every finding.
- Propose fixes, not just problems. A finding without a solution is half-finished work.
- Group subagent work to keep each focused (2-3 concerns max per agent).
- Calibrate severity honestly. A style issue is Informational, not Medium. An `unwrap()` on a `Some` that's guaranteed by the previous line is not High.
- For state transitions and fund flows, verify complete accounting (inputs = outputs + fees).
- Check both the Rust code layer and any contract/protocol-level validation before concluding a finding is valid.
- `debug_assert!` is not a production guard — it compiles to nothing in release builds. If correctness depends on a `debug_assert!`, that's a real finding.
- For consensus code: if two honest validators could produce different results from the same input, that's at minimum High severity.
- Group Phase 3 subagent work by domain (security, consensus, docs/tests, architecture) for focused analysis.
- Run `make public-tests` when reviewing changes that touch consensus or execution crates — don't rely solely on reading test code.
