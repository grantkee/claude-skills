# tn-rust-engineer

Orchestrator skill for Rust development in the telcoin-network repo. Drives a 5-phase pipeline that spawns specialized subagents for task analysis, implementation planning, code writing, verification, and review. The skill itself never writes code — it coordinates agents that do.

## Pipeline Flow

```
Phase 1: tn-task-analyzer      → understand the task
Phase 2: tn-impl-planner       → plan the implementation
Phase 2.5: task-decomposer     → optimize for parallelism (conditional)
Phase 3: tn-rust-engineer      → write code (parallel where possible)
Phase 4: tn-verifier           → verify correctness
  └─ On failure: tn-debugger   → diagnose, then retry Phase 3
Final: review-agent            → final validation
```

## Subagents

### Phase 1 — `tn-task-analyzer`

**Receives:** task description, target files/crates, repo path.
**Produces:** layer identification, affected files/crates, boundary crossings, existing patterns.
**Role:** Understands what the task touches and finds reusable patterns in the codebase before any code is planned.

### Phase 2 — `tn-impl-planner`

**Receives:** full Phase 1 analysis, original task description.
**Produces:** affected crates in dependency order, type placement, channel strategy, implementation steps, constraints.
**Role:** Turns analysis into a concrete implementation plan. If the plan surfaces risks or open questions, they are presented to the user before proceeding.

### Phase 2.5 — `task-decomposer` (conditional)

**Receives:** full Phase 2 implementation plan.
**Produces:** parallel/sequential task breakdown with agent assignments (`tn-rust-engineer` for coding tasks).
**Role:** Splits multi-task plans into waves that can run in parallel. Skipped when the plan has only 1 coding task.

### Phase 3 — `tn-rust-engineer` (agent)

**Receives:** specific task from decomposition (or full plan if single task), files to modify, constraints from Phase 2.
**Produces:** production Rust code following codebase conventions.
**Role:** Writes the actual code. Spawned as a single agent for simple tasks, or multiple agents in parallel/sequential waves for complex plans.

### Phase 4 — `tn-verifier`

**Receives:** list of all modified crates and files from Phase 3.
**Produces:** pass/fail with diagnostics.
**Role:** Runs `cargo check`, `cargo fmt`, `cargo clippy`, and `cargo nextest` scoped to changed crates. On failure, spawns `tn-debugger` internally and returns a diagnosis.

### Phase 4 (on failure) — `tn-debugger`

**Receives:** verification failure output.
**Produces:** classified diagnosis with fix instructions.
**Role:** Classifies the failure, diagnoses root cause, and provides fix instructions. After diagnosis, the orchestrator re-enters Phase 3 with the fix, then re-verifies.

### Final — `review-agent`

**Receives:** all changes from the pipeline.
**Produces:** final review gate before presenting results to the user.
**Role:** Validates the complete changeset for correctness, style, and safety.

## Error Handling

- **Ambiguous tasks:** Phase 1 asks the user for clarification before Phase 2 begins.
- **Architectural concerns:** Phase 2 presents options to the user before Phase 3.
- **Verification failures:** Phase 4 retries up to **2 times** (diagnose via `tn-debugger`, fix via `tn-rust-engineer`, re-verify). If still failing after 2 attempts, reports the failure with full context.
- **Unexpected output:** Any phase producing unexpected results stops the pipeline and reports to the user rather than guessing.
- **Phase 4 is never skipped** — all code must be verified before review.

## Trigger Keywords

`implement`, `fix`, `add`, `build`, `write code`, `refactor`, `new feature`, `bug fix`, `change`, `update`, `modify`, `extend`, `port`, `migrate`, `add support for`, `wire up`, `hook up`, `integrate`

## Not This Skill

- Code review → `tn-review`
- E2E debugging → `tn-debug-e2e`
- Contract review → `tn-review-contracts`
- Writing tests → `tn-write-e2e` / `tn-write-proptest`
