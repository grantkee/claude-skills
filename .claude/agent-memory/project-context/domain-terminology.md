---
name: domain-terminology
description: Key terminology and non-obvious design patterns in the claude-extensions repo
type: project
---

This repo uses "skill" and "agent" as distinct concepts:

- **Skill** = slash-command invoked interactively by a human during a Claude Code session (`/skill-name`). Lives at `skills/<name>/SKILL.md`. Provides a prompt template the LLM executes inline.
- **Agent** = autonomous subagent spawned programmatically by an orchestrator. Lives at `agents/<name>.md`. Has YAML frontmatter with `description` that drives automatic spawn detection. Runs in isolation with its own context window.

The `description` frontmatter on agents is load-bearing — Claude Code reads it to decide when to auto-spawn the agent. It must clearly state trigger conditions in the second person.

The `project-context` agent is always spawned FIRST in any plan mode session — this is enforced both by `CLAUDE.md` policy and by a `UserPromptSubmit` hook in `settings.local.json`.

The `tn-rust-engineer` agent invokes the `tn-rust-engineer` skill via the `Skill` tool — the agent is the orchestration wrapper, the skill provides the detailed Rust engineering prompt.

Agent memory lives at `~/.claude/agent-memory/<agent-name>/` and is NOT version-controlled — it's machine-local. The repo only stores skill and agent definitions, not memory.
