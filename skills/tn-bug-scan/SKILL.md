---
name: tn-bug-scan
description: "Deep bug hunt for the telcoin-network codebase (Rust + Solidity submodule) across 9 phases with specialized agents. Bug-hunter framing — asks 'how does this fail in production?' not 'how does an attacker exploit this?'. Covers concurrency, determinism, consensus correctness, state atomicity, panic surface, fork risk, and error propagation. Produces bug tickets with repro + failure mode per finding. Triggers on /tn-bug-scan or tn bug scan or telcoin bug hunt."
---

# tn-bug-scan

Deep bug hunt for telcoin-network. Nine phases of iterative Feynman + state-check analysis, reframed from adversarial auditing to production-failure hunting. Output: bug tickets with concrete repro conditions, failure mode, affected invariant, and recommended fix.

## Activation

- User says `/tn-bug-scan`, `tn bug scan`, `telcoin bug hunt`, `bug scan telcoin`, or `hunt bugs in tn`
- User wants to find correctness failures (crash / stall / fork / divergence / silent wrong state) in telcoin-network code

Different from `/tn-nemesis-scan`: tn-bug-scan produces bug tickets framed around production events; tn-nemesis-scan produces attack paths framed around adversaries. Same codebase, different lens.

## Invocation Format

```
/tn-bug-scan [target] [--full] [--path <glob>] [--hints "..."] [--fresh]
```

Default target = **current branch PR diff vs main** (`.rs` and `.sol` files only).

Examples:
- `/tn-bug-scan` — scan the current branch's changes vs main
- `/tn-bug-scan --full` — scan all of `crates/` + `tn-contracts/src/`
- `/tn-bug-scan --path "crates/consensus/primary/**/*.rs"` — glob-scoped scan
- `/tn-bug-scan crates/state-sync/ --hints "certificate fetcher race"` — explicit target + hints
- `/tn-bug-scan --fresh` — force Phase -1 domain-pattern regeneration

## Execution

### Step 1: Resolve Target Scope

- **`--full`** → target = `crates/` + `tn-contracts/src/` (entire Rust + Solidity tree, excluding tests)
- **`--path <glob>`** → target = the glob (can repeat the flag for multiple globs)
- **Explicit `[target]` arg** → target = the user-supplied arg
- **No arg, no flag** → target = current branch PR diff vs `main`, filtered to `.rs` and `.sol`:
  ```bash
  git -C /Users/grant/coding/telcoin/telcoin-network diff --name-only main...HEAD \
    | grep -E '\.(rs|sol)$' \
    | grep -v -E '(test|bench|e2e-tests|test_utils)'
  ```
  If the diff is empty, tell the user the branch has no Rust/Solidity changes and stop.

### Step 2: Parse Optional Arguments

- **`--hints`** — extract the quoted string after `--hints`. Default: `"none"`.
- **`--fresh`** — if present, skip the cache check and force Phase -1 re-discovery.

### Step 3: Resolve Paths

- Target repo path: `/Users/grant/coding/telcoin/telcoin-network`
- Skill references path (absolute): compute from this skill's location; should resolve to `.../skills/tn-bug-scan/references/`

### Step 4: Create Output Directories

```bash
mkdir -p /Users/grant/coding/telcoin/telcoin-network/.audit/tn-bug-scan/research
mkdir -p /Users/grant/coding/telcoin/telcoin-network/.audit/findings
```

### Step 5: Cache Check

Determine if Phase -1 domain discovery is needed.

```bash
if [ -f /Users/grant/coding/telcoin/telcoin-network/.audit/bug-domain-patterns.md ]; then
  head -5 /Users/grant/coding/telcoin/telcoin-network/.audit/bug-domain-patterns.md
fi
git -C /Users/grant/coding/telcoin/telcoin-network rev-parse --short HEAD
```

The cache is **valid** when ALL of:
- The file exists
- The `_Git hash:_` line matches current `git rev-parse --short HEAD`
- The `_Target scope:_` line matches the requested scope
- The `_User hints:_` line matches the provided hints
- The `--fresh` flag was NOT passed

Set `discovery_needed = true` if the cache is invalid or missing. Set `discovery_needed = false` if the cache is valid.

### Step 6: Spawn the Orchestrator

```
Agent({
  subagent_type: "tn-bug-orchestrator",
  description: "Run tn-bug-scan pipeline",
  prompt: "Run the full tn-bug-scan pipeline on the following target scope.

Target scope: [resolved target from Step 1 — list of files/directories]
Target repo path: /Users/grant/coding/telcoin/telcoin-network
References path: [absolute path to skills/tn-bug-scan/references/]
Domain hints: [user hints or 'none']
Discovery needed: [true/false]

All agents MUST read references/bug-core-rules.md, references/bug-patterns.md, and references/tn-hotspots.md.
Phase 7 (reporter) MUST follow references/bug-ticket-format.md exactly.

[If discovery_needed is true:]
Run Phase -1 (Domain Discovery) FIRST:
- Phase -1a: Spawn tn-bug-strategy with project-context, target scope, hints, references path
- Phase -1b: Spawn parallel tn-bug-researcher agents (one per research topic)
- Phase -1c: Compile fragments into .audit/bug-domain-patterns.md with cache metadata

[If discovery_needed is false:]
Skip Phase -1. Domain patterns cached at .audit/bug-domain-patterns.md. Verify the file exists and is non-empty before proceeding; if missing, run Phase -1 anyway.

Then execute all 9 phases in order, with all agents reading .audit/bug-domain-patterns.md for domain context:
- Phase 0+1 (parallel): tn-bug-recon + tn-bug-mapper
- Phase 2: tn-bug-feynman (full mode)
- Phase 3: tn-bug-state-check (full mode)
- Phase 4: feedback loop (max 3 iterations; spawn tn-bug-feynman and tn-bug-state-check in targeted mode per iteration)
- Phase 5: tn-bug-scenario
- Phase 6: tn-bug-verifier (loads tn-domain-* skills as needed for invariant cross-check)
- Phase 7: tn-bug-reporter

Write phase outputs to /Users/grant/coding/telcoin/telcoin-network/.audit/tn-bug-scan/
Write final reports to:
  /Users/grant/coding/telcoin/telcoin-network/.audit/findings/tn-bug-scan-verified.md
  /Users/grant/coding/telcoin/telcoin-network/.audit/findings/tn-bug-scan-raw.md

Present a concise summary when complete."
})
```

### Step 7: Relay Orchestrator Summary

After the orchestrator returns, relay its summary to the user with paths to both report files. If CRITICAL findings include an escalation recommendation to `tn-security-eval`, surface that recommendation in the summary.
