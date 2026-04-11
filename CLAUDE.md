## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update 'tasks/lessons.md" with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixes
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Fix failing tests without being told how

### 7. Project Context Agent
- At the start of every plan, spawn the `project-context` agent to analyze/refresh the repo's architecture
- The agent writes `.claude/project-context.md` — point all subagents to read this file
- For multi-repo tasks, spawn one instance per unique git remote
- Do NOT re-analyze if the existing context file is still fresh

## Task Management
1. **Plan First**: Write plan to "tasks/todo.md" with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to 'tasks/todo.md"
6. **Capture Lessons**: Update 'tasks/lessons.md" after corrections

## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimat Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Agent Triggering Manifest

Agents must be spawned proactively based on detected conditions, not reactively after the user asks. Claude's agent-spawning decisions should be driven by the agent's `description` frontmatter.

### Automatic Spawn Rules

| Condition Detected | Agent to Spawn | Priority |
|---|---|---|
| Entering plan mode | `project-context` | FIRST — before any other agent |
| Plan design complete with coding tasks | `task-decomposer` | Before presenting plan to user |
| Implementation tasks identified | `tn-rust-engineer` | One per task, parallel |
| Error output / stack trace / test failure | `debug-orchestrator` | Immediate |
| E2E tests needed after implementation | `write-e2e-agent` | After implementation wave |
| Property tests needed | `write-proptest-agent` | Parallel with write-e2e-agent |
| Documentation needed | `write-docs-agent` | After test wave |
| Final validation before presenting work | `review-agent` | Last step |
| `/security-eval` invoked | 7 security agents | All parallel |

### Key Principle
If you're about to do something an agent is designed for, spawn the agent instead of doing it yourself. Agents provide context isolation, parallel execution, and specialized expertise.

## Plan Mode Entry Checklist

**CRITICAL: Every plan mode session MUST follow this checklist. No exceptions.**

1. **Spawn `project-context` agent FIRST** — before designing the plan, before any other agents
2. Wait for project-context to return (or confirm context is fresh)
3. Design the plan with full architecture context
4. Ask me to confirm design decisions when considering more than one option
5. **Spawn `task-decomposer` agent** — decompose before presenting to user
6. Present the decomposed plan for user approval

If you skip step 1, the plan will lack architecture context and downstream agents will waste time re-exploring the codebase.

## Implementation Pipeline

After plan approval, execute in waves:

```
Wave 0: project-context (if not already fresh)
Wave 1-N: tn-rust-engineer agents (parallel per wave, sequential across waves)
Wave N+1: write-e2e-agent + write-proptest-agent (parallel)
Wave N+2: write-docs-agent
Wave N+3: review-agent (final validation)
```

Each wave completes before the next begins. Within a wave, maximize parallelism.

## Debug Routing

When error signals appear in the conversation, spawn `debug-orchestrator` immediately:

| Signal | Routed To |
|---|---|
| E2E test failure | `debug-e2e` skill |
| Panic / crash / unwrap failure | `harden-tn` skill (panic audit) |
| Logic bug / state corruption | `nemesis` skill (deep audit) |
| Build failure | Direct diagnosis |
| After diagnosis complete | `tn-rust-engineer` for fix |

Do NOT attempt to debug manually — always route through `debug-orchestrator` for systematic triage.

## Security Evaluation

Run `/security-eval` when reviewing code.

The security-eval skill spawns 10 parallel agents:
1. `consensus-safety` — BFT assumptions, quorum logic
2. `state-transitions` — invariant violations, partial operations
3. `crypto-correctness` — signatures, hashing, key management
4. `dos-vectors` — resource exhaustion, unbounded allocations
5. `determinism-verifier` — HashMap, SystemTime, randomness
6. `contract-safety` — access control, reentrancy, accounting
7. `dependency-auditor` — new crates, CVEs, supply chain
8. `nemesis-auditor` — deep business logic, state inconsistency
9. `dread-evaluator` — attacker-perspective DREAD risk scoring
10. `stride-threat-model` — STRIDE threat classification

Severity scale: CRITICAL (consensus break/fund loss) → HIGH → MEDIUM → LOW → INFO
