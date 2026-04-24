---
name: tn-rust-engineer
description: |
  Orchestrator skill for Rust development in the telcoin-network repo.
  Spawns specialized subagents for task analysis, implementation planning,
  code writing, and verification.
  Trigger on: "implement", "fix", "add", "build", "write code", "refactor", "new feature",
  "bug fix", "change", "update", "modify", "extend", "port",
  "migrate", "add support for", "wire up", "hook up", "integrate".
  Do NOT trigger for: code review (use tn-review), e2e debugging (use tn-debug-e2e),
  contract review (use tn-review-contracts), writing tests (use tn-write-e2e / tn-write-proptest).
---

# Telcoin Network Rust Engineer — Orchestrator

This skill orchestrates Rust development in the telcoin-network codebase by spawning specialized subagents for each phase. It does NOT contain conventions or write code itself — conventions live in the `tn-rust-skills` skill, code writing lives in the `tn-rust-engineer` agent.

## Pipeline Overview

```
Phase 1: tn-task-analyzer      → understand the task; emit domains: [...]
Phase 2: tn-impl-planner       → plan the implementation (loads domain skills)
Phase 2.5: task-decomposer     → optimize for parallelism (if 2+ coding tasks)
Phase 3: tn-rust-engineer      → write code (parallel where possible; loads domain skills)
Phase 3.5: tn-domain-reviewer  → domain-invariant gate (loads domain skills)
  └─ On CHANGES_REQUESTED: re-enter Phase 3 with reviewer findings (max 2 iterations)
  └─ On ESCALATE: surface to user — plan needs revision
Phase 4: tn-verifier           → verify correctness (build/lint/test)
  └─ On failure: tn-debugger   → diagnose (loads domain skills), then re-enter Phase 3 with fix
Final: review-agent            → cross-cutting final validation (style, architecture)
```

## The `domains:` parameter

Starting in Phase 1, the orchestration threads a `domains: [...]` list through every downstream spawn. Each entry names a `tn-domain-*` skill that the receiving agent loads to gain expert context for the layer it's working in.

Recognized domain names: `epoch`, `execution`, `consensus`, `storage`, `worker`, `contracts`, `networking`. Each maps 1:1 to a `tn-domain-{name}` skill.

The path-based mapping (used by tn-task-analyzer to derive `domains:`):

| Path / signal | Domain |
|---|---|
| `crates/node/src/manager/**`, `crates/epoch-manager/**`, anything touching `RunEpochMode` or `GasAccumulator` | `epoch` |
| `crates/engine/**`, `crates/tn-reth/**` (except contracts), anything calling `reth_env.*` | `execution` |
| `crates/consensus/{primary,worker,executor}/**` excluding pure batch-building | `consensus` |
| `crates/storage/**`, anything touching the `Database` trait or table definitions | `storage` |
| `crates/batch-builder/**`, `crates/consensus/worker/**` for batch construction | `worker` |
| `crates/tn-reth/src/system_calls.rs`, anything firing `concludeEpoch`/`applyIncentives`/`applySlashes` | `contracts` |
| `crates/network-libp2p/**`, `crates/state-sync/**` | `networking` |

A change touching multiple paths gets multiple domains. Pass the full set to every downstream spawn.

## Orchestration Process

### Phase 1: Task Analysis

Spawn `tn-task-analyzer` agent with:
- The task description from the user
- Any target files or crates mentioned
- The path to the target repo

Wait for the analysis output: layer identification, affected files/crates, boundary crossings, existing patterns, **and the derived `domains: [...]` list**.

Capture `domains: [...]` from the analyzer output — it's threaded through every subsequent spawn.

### Phase 2: Implementation Planning

Spawn `tn-impl-planner` agent with:
- The full Phase 1 analysis output (including `domains:`)
- The original task description for context

The planner loads each `tn-domain-{name}` skill in `domains:` to plan with domain invariants in mind.

Wait for the implementation plan: affected crates in dependency order, type placement, channel strategy, implementation steps, constraints, **plus any domain-specific risks the planner surfaces from the loaded skills**.

**If the plan surfaces risks or open questions**, present them to the user before proceeding.

### Phase 2.5: Task Decomposition (conditional)

If the implementation plan has **2 or more coding tasks**, spawn `task-decomposer` agent with:
- The full Phase 2 implementation plan
- Instructions to assign `tn-rust-engineer` as the agent type for coding tasks

Wait for the decomposition: parallel/sequential task breakdown with agent assignments.

If the plan has only 1 coding task, skip this phase.

### Phase 3: Code Writing

Spawn `tn-rust-engineer` agent(s) based on the decomposition:
- **Single task**: spawn 1 agent with the implementation plan and target files
- **Multiple independent tasks**: spawn agents in parallel, one per task
- **Sequential tasks**: spawn agents in waves, waiting for each wave to complete

Each agent receives:
- Its specific task from the decomposition (or the full plan if single task)
- The list of files to modify
- Any constraints from Phase 2
- **`domains: [...]`** — the engineer loads these `tn-domain-*` skills before writing code

If a decomposed task touches a subset of the overall `domains:`, narrow the parameter for that task's spawn. The orchestrator owns the per-task domain scoping.

### Phase 3.5: Domain Review

After Phase 3 agents complete (and before Phase 4), spawn `tn-domain-reviewer` for each implementation task with:
- `domains: [...]` — same set the engineer used
- `files: [...]` — the files modified by that task
- `task_summary` — short description of the task

The reviewer returns one of:

- **APPROVED** — proceed to Phase 4
- **CHANGES_REQUESTED** — re-spawn the engineer with the reviewer findings as fix instructions, then re-spawn the reviewer. **Cap at 2 iterations.**
- **ESCALATE** — surface to the user; the implementation plan likely needs revision

If the same Critical finding persists across 2 iterations, force ESCALATE rather than running a third refactor.

### Phase 4: Verification

After Phase 3.5 returns APPROVED for all tasks, spawn `tn-verifier` agent with:
- The list of all modified crates and files (collected from Phase 3 outputs)

**On success**: proceed to Final phase.

**On failure**: `tn-verifier` spawns `tn-debugger` internally and returns a diagnosis. The debugger receives `domains: [...]` and loads matching skills. Then:
1. Re-spawn `tn-rust-engineer` agent with the fix instructions from the diagnosis (and the same `domains:`)
2. Re-spawn `tn-domain-reviewer` (Phase 3.5) on the fix
3. Re-spawn `tn-verifier` to validate
4. Repeat up to 2 times. If still failing after 2 fix attempts, report to the user with full context.

### Final: Review

Spawn `review-agent` for cross-cutting final validation (style, architecture, things outside any single domain's scope) before presenting results to the user. The domain-specific gate has already run in Phase 3.5.

## Error Handling

- If any phase produces unexpected output, stop and report to the user rather than guessing
- If Phase 1 finds the task is ambiguous or under-specified, ask the user for clarification before Phase 2
- If Phase 2 surfaces architectural concerns, present options to the user before Phase 3
- Never skip Phase 4 — all code must be verified before review
