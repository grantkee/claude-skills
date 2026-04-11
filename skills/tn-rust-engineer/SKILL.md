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
Phase 1: tn-task-analyzer      → understand the task
Phase 2: tn-impl-planner       → plan the implementation
Phase 2.5: task-decomposer     → optimize for parallelism (if 2+ coding tasks)
Phase 3: tn-rust-engineer      → write code (parallel where possible)
Phase 4: tn-verifier           → verify correctness
  └─ On failure: tn-debugger   → diagnose, then re-enter Phase 3 with fix
Final: review-agent            → final validation
```

## Orchestration Process

### Phase 1: Task Analysis

Spawn `tn-task-analyzer` agent with:
- The task description from the user
- Any target files or crates mentioned
- The path to the target repo

Wait for the analysis output: layer identification, affected files/crates, boundary crossings, existing patterns.

### Phase 2: Implementation Planning

Spawn `tn-impl-planner` agent with:
- The full Phase 1 analysis output
- The original task description for context

Wait for the implementation plan: affected crates in dependency order, type placement, channel strategy, implementation steps, constraints.

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

### Phase 4: Verification

After all Phase 3 agents complete, spawn `tn-verifier` agent with:
- The list of all modified crates and files (collected from Phase 3 outputs)

**On success**: proceed to Final phase.

**On failure**: `tn-verifier` spawns `tn-debugger` internally and returns a diagnosis. Then:
1. Re-spawn `tn-rust-engineer` agent with the fix instructions from the diagnosis
2. Re-spawn `tn-verifier` to validate the fix
3. Repeat up to 2 times. If still failing after 2 fix attempts, report the failure to the user with full context.

### Final: Review

Spawn `review-agent` for final validation of all changes before presenting results to the user.

## Error Handling

- If any phase produces unexpected output, stop and report to the user rather than guessing
- If Phase 1 finds the task is ambiguous or under-specified, ask the user for clarification before Phase 2
- If Phase 2 surfaces architectural concerns, present options to the user before Phase 3
- Never skip Phase 4 — all code must be verified before review
