---
name: claude-extensions domain terminology
description: Key terms and non-obvious architectural patterns in the claude-extensions-personal repo
type: project
---

**Skill vs Agent distinction:** A "skill" is a passive SKILL.md prompt invoked with `/skill-name` or via the `Skill` tool from inside an agent. An "agent" is an active subagent definition with frontmatter (name, tools, model, color, memory) that runs autonomously in its own context window. Agents use skills; skills do not spawn agents.

**Wrapper agents:** Several agents (write-e2e-agent, write-proptest-agent, write-docs-agent, review-agent) exist solely to wrap a single skill with proper context loading and output verification. They are thin shells, not independent logic.

**Target repo vs this repo:** This repo holds the skill/agent definitions. The target repo (telcoin-network) is where those skills actually do work. `project-context.md` is written to the *target* repo's `.claude/` directory, not to this extensions repo. When agents say "read .claude/project-context.md", they mean in the working directory they are spawned in.

**Nemesis composition:** The `nemesis` skill runs `feynman-auditor` (Stage 1) + `state-inconsistency-auditor` (Stage 2) + a fusion feedback loop (Stage 3) to find bugs at the intersection of both approaches. `feynman-auditor` and `state-inconsistency-auditor` also exist as standalone skills — they are not agents.

**Security eval is skill-driven:** `security-eval` is a *skill* (not an agent) that orchestrates 7 named *agents* in parallel. This is unusual — most skills are passive prompts, but security-eval actively spawns subagents.

**CLAUDE.md is dual-homed:** The same `CLAUDE.md` file lives in the repo root and gets installed to `~/.claude/CLAUDE.md` globally. It governs plan mode, agent spawning rules, and the orchestration pipeline for ALL projects, not just telcoin-network.

**Why:** These distinctions matter when adding new entries — a new piece of domain logic goes in a skill, a new autonomous worker goes in an agent. Wrapper agents should stay thin.
