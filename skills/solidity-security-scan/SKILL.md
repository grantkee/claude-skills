---
name: solidity-security-scan
description: |
  Comprehensive security scan for Solidity projects. One-command entry point that orchestrates
  3-4 specialized Solidity agents in parallel: solidity-sentinel (defensive analysis),
  solidity-nemesis (adversarial exploit hypotheses), solidity-gas-architect (gas optimization),
  and optionally solidity-deploy-auditor (if .s.sol deployment scripts are in scope).
  Consolidates all reports into a unified summary with cross-report pattern analysis.
  Generic — works on any Foundry, Hardhat, or bare Solidity project.
  Trigger on: "solidity security scan", "scan solidity contracts", "audit solidity", "solidity audit",
  "security scan contracts", "scan contracts", "full solidity review"
---

# Solidity Security Scan Orchestrator

One-command security scan for Solidity projects. Spawns 3-4 specialized agents in parallel, each covering a distinct analysis domain, then consolidates all reports into a unified summary with cross-report pattern analysis.

## Agents Orchestrated

| Agent | Domain | Always/Conditional | Output File |
|-------|--------|-------------------|-------------|
| `solidity-sentinel` | Defensive analysis (aderyn + slither + manual) | Always | `solidity-sentinel-report.md` |
| `solidity-nemesis` | Adversarial exploit hypotheses with economics | Always | `nemesis.md` + `invariants.md` |
| `solidity-gas-architect` | Gas optimization with scrutineer validation | Always | `gas-report.md` |
| `solidity-deploy-auditor` | Deployment script security (5 parallel subagents) | If `.s.sol` files in scope | `solidity-deployment-report.md` |

## Severity Scale

| Level | Definition | Examples |
|-------|-----------|---------|
| **CRITICAL** | Direct fund loss, unauthorized transfer, complete access control bypass | Reentrancy with value, unprotected selfdestruct, proxy storage collision |
| **HIGH** | Conditional fund loss, broken accounting, governance takeover | Flash loan exploitation, initialization gap, oracle manipulation |
| **MEDIUM** | DoS vectors, griefing, precision loss, missing critical events | Unbounded loops, front-running windows, stale oracle reads |
| **LOW** | Gas inefficiencies with security implications, minor validation gaps | Missing zero-address checks, suboptimal storage packing |
| **INFO** | Code quality, best practices, documentation | NatSpec gaps, naming conventions, style |

## Process

### Phase 1: Context & Scope

#### Step 1: Spawn Project Context

Spawn a `project-context` agent against the target path to ensure `.claude/project-context.md` is fresh. If the file already exists and the date header is within 24 hours, skip this step.

#### Step 2: Detect Scope

Determine what Solidity files to analyze based on user input:

**PR number provided:**
```bash
gh pr diff <number> --name-only | grep '\.sol$'
```

**Branch provided or current branch differs from main:**
```bash
git diff main...HEAD --name-only | grep '\.sol$'
```

**Specific files provided:**
Use the provided file list directly.

**No scope specified — full project scan:**
```bash
find <target_path> -name "*.sol" \
  -not -path "*/node_modules/*" \
  -not -path "*/lib/*" \
  -not -path "*/out/*" \
  -not -path "*/cache/*" \
  -not -path "*/test/*" \
  -not -path "*/script/*" | head -200
```

#### Step 3: Enumerate & Classify

1. **Count Solidity files and LOC** for report metadata:
   ```bash
   find <target_path> -name "*.sol" \
     -not -path "*/node_modules/*" \
     -not -path "*/lib/*" \
     -not -path "*/out/*" \
     -not -path "*/cache/*" | xargs wc -l 2>/dev/null | tail -1
   ```

2. **Check for `.s.sol` files** in scope to determine deploy-auditor inclusion:
   ```bash
   find <target_path> -name "*.s.sol" \
     -not -path "*/node_modules/*" \
     -not -path "*/lib/*" \
     -not -path "*/out/*" \
     -not -path "*/cache/*"
   ```
   If `.s.sol` files exist, set `DEPLOY_SCRIPTS_IN_SCOPE = true`.

3. **Identify project type**:
   - Check for `foundry.toml` → Foundry
   - Check for `hardhat.config.js` or `hardhat.config.ts` → Hardhat
   - Otherwise → bare Solidity

#### Step 4: Validate Scope

If zero `.sol` files are found, stop and report:
> "No Solidity files found in scope. Check the target path and any filters applied."

If the scope is very large (100+ files), warn the user and suggest narrowing.

### Phase 2: Parallel Analysis

Spawn all agents simultaneously using the Agent tool. Each agent is self-contained — it handles its own subagent spawning, verification, and report generation internally.

**CRITICAL: Spawn all agents in a single message with multiple Agent tool calls to maximize parallelism.**

#### Agent 1: Solidity Sentinel

```
Agent({
  subagent_type: "general-purpose",
  description: "Solidity sentinel defensive analysis",
  prompt: "You are being spawned as part of a solidity-security-scan orchestration.

Read the agent definition at <target_path_repo>/agents/solidity-sentinel.md and follow its instructions exactly.

Target path: <target_path>
Scope: <scope_description>
Solidity files in scope:
<file_list>

Read .claude/project-context.md at the target path for architecture context.

Execute all phases of the solidity-sentinel agent and write the final report to:
<target_path>/solidity-sentinel-report.md

Report back with a brief summary of findings by severity count."
})
```

Replace `<target_path_repo>` with the path to the claude-extensions-personal repo (where agent definitions live), and `<target_path>` with the project being analyzed.

#### Agent 2: Solidity Nemesis

```
Agent({
  subagent_type: "general-purpose",
  description: "Solidity nemesis adversarial analysis",
  prompt: "You are being spawned as part of a solidity-security-scan orchestration.

Read the agent definition at <target_path_repo>/agents/solidity-nemesis.md and follow its instructions exactly.

Target path: <target_path>
Scope: <scope_description>
Solidity files in scope:
<file_list>

Read .claude/project-context.md at the target path for architecture context.

Execute all phases of the solidity-nemesis agent and write the reports to:
- <target_path>/nemesis.md (exploit hypothesis report)
- <target_path>/invariants.md (property map from invariant auditor)

Report back with a brief summary: top exploit hypothesis, count by severity, vectors with no viable path."
})
```

#### Agent 3: Solidity Gas Architect

```
Agent({
  subagent_type: "general-purpose",
  description: "Solidity gas optimization analysis",
  prompt: "You are being spawned as part of a solidity-security-scan orchestration.

Read the agent definition at <target_path_repo>/agents/solidity-gas-architect.md and follow its instructions exactly.

Target path: <target_path>
Scope: <scope_description>
Solidity files in scope:
<file_list>

Read .claude/project-context.md at the target path for architecture context.

Execute all phases of the solidity-gas-architect agent and write the final report to:
<target_path>/gas-report.md

Report back with a brief summary: total optimizations proposed, estimated savings, scrutineer flags."
})
```

#### Agent 4: Solidity Deploy Auditor (Conditional)

**Only spawn if `DEPLOY_SCRIPTS_IN_SCOPE = true`.**

```
Agent({
  subagent_type: "general-purpose",
  description: "Solidity deployment script audit",
  prompt: "You are being spawned as part of a solidity-security-scan orchestration.

Read the agent definition at <target_path_repo>/agents/solidity-deploy-auditor.md and follow its instructions exactly.

Target path: <target_path>
Deployment scripts in scope:
<s_sol_file_list>

Read .claude/project-context.md at the target path for architecture context.

Execute all phases of the solidity-deploy-auditor agent and write the final report to:
<target_path>/solidity-deployment-report.md

Report back with a brief summary of findings by severity and subagent."
})
```

### Phase 3: Consolidation

After ALL parallel agents complete, spawn a `general-purpose` consolidation subagent.

```
Agent({
  description: "Consolidate Solidity security scan reports",
  prompt: "You are the consolidation agent for a solidity-security-scan. Your job is to read all individual reports and produce a unified summary.

Read the following report files at <target_path>:
1. solidity-sentinel-report.md
2. nemesis.md
3. invariants.md
4. gas-report.md
[5. solidity-deployment-report.md — if it exists]

Produce a consolidated summary file at <target_path>/solidity-security-scan-summary.md with this structure:

---

# Solidity Security Scan Summary

## Scan Metadata
- **Target**: [target path]
- **Project type**: [Foundry / Hardhat / Bare]
- **Solidity files analyzed**: [count]
- **Total LOC**: [count]
- **Scan date**: [date]
- **Agents executed**: [list which agents ran]

## Executive Summary

[2-3 paragraphs: overall risk assessment, what the protocol does, where value concentrates, and the most significant findings across all agents. Write for a human security reviewer.]

**Overall Risk Level**: [CRITICAL / HIGH / MEDIUM / LOW / CLEAN]
**Total findings**: [count across all reports, by severity]

## Sentinel Digest

- [3-5 sentences summarizing defensive findings]
- Confirmed findings: [count] | False positives eliminated: [count]
- Cross-tool agreement: [which findings were caught by multiple analysis tracks]
- Key categories: [access-control, reentrancy, value-flow, etc.]

## Nemesis Digest

- Top exploit hypothesis: [one-line with expected profit]
- Total hypotheses: [count by severity]
- Invariants verified unbreakable: [count from invariants.md]
- Vectors with no viable path: [list]

## Gas Architect Digest

- Total optimization proposals: [count]
- Estimated total savings: [gas amount]
- Scrutineer flags: [any safety concerns raised]
- Top 3 optimizations: [brief list]

## Deploy Auditor Digest (if applicable)

- Key management findings: [summary]
- Proxy atomicity: [summary]
- Front-running windows: [summary]
- Environment assumptions: [summary]

## Cross-Report Patterns

Issues identified by multiple agents carry the highest confidence:

| Pattern | Agents | Severity | Description |
|---------|--------|----------|-------------|
| [pattern] | sentinel + nemesis | [sev] | [one-line] |

[Highlight where sentinel found a bug that nemesis chained into an exploit hypothesis.
Highlight where gas optimizations interact with security findings.
Highlight where deployment issues relate to contract-level vulnerabilities.]

## Priority Action Items

Numbered list ordered by severity, with references to which report contains the details:

1. **[CRITICAL]** [description] — see sentinel-report Finding N / nemesis EXP-N
2. **[HIGH]** [description] — see sentinel-report Finding N
3. ...

---

After writing the file, return the full content of the summary."
})
```

### Phase 4: Present Results

After the consolidation agent returns, output a concise summary to the conversation:

```
## Solidity Security Scan Complete

**Overall Risk**: [CRITICAL / HIGH / MEDIUM / LOW / CLEAN]
**Target**: [path] ([Foundry/Hardhat/Bare], [N] contracts, [N] LOC)

### Findings by Severity
| Severity | Count |
|----------|-------|
| Critical | N |
| High     | N |
| Medium   | N |
| Low      | N |
| Info     | N |

### Top Findings
1. [one-line description with severity and source agent]
2. ...
3. ...

### Agents Executed
- solidity-sentinel → solidity-sentinel-report.md
- solidity-nemesis → nemesis.md + invariants.md
- solidity-gas-architect → gas-report.md
[- solidity-deploy-auditor → solidity-deployment-report.md]

### Reports
- **Full summary**: <target_path>/solidity-security-scan-summary.md
- **Sentinel report**: <target_path>/solidity-sentinel-report.md
- **Nemesis report**: <target_path>/nemesis.md
- **Invariant map**: <target_path>/invariants.md
- **Gas report**: <target_path>/gas-report.md
[- **Deployment report**: <target_path>/solidity-deployment-report.md]
```

Keep this concise — full details are in the individual reports and the summary file.

## Rules

- **Spawn all Phase 2 agents in a single message.** Parallel execution is the entire point of this skill. Never spawn them sequentially.
- **Do not duplicate agent work.** Each agent handles its own subagent spawning, verification, and report writing. The orchestrator's job is scope detection, agent spawning, consolidation, and presentation.
- **Do not present partial results.** Wait for ALL agents to complete before spawning the consolidation agent.
- **Deploy-auditor is conditional.** Only spawn when `.s.sol` files are found in scope. Do not spawn it for projects without deployment scripts.
- **Provide the agent definition path.** Each spawned agent needs the path to its agent definition file in this repo so it can read its full instructions.
- **Target path vs repo path.** The target path is the Solidity project being analyzed. The repo path is this claude-extensions-personal directory where agent definitions live. Keep these distinct.
- **If an agent fails, report it.** If a subagent errors out (e.g., tool not installed, compilation failure), include the failure in the summary rather than silently dropping it.
- **No unverified findings.** Each agent handles its own verification internally. The consolidation agent reads verified reports only.

## Expected Agent Counts

| Phase | Agents | Notes |
|-------|--------|-------|
| 1 | 0-1 | project-context (if needed) |
| 2 | 3-4 | Core analysis agents (parallel) |
| 2 (internal) | ~15-25 | Subagents spawned by the core agents internally |
| 3 | 1 | Consolidation agent |
| **Total** | **~20-30** | Typical full scan |

## What This Skill Does NOT Do

- Does not modify Solidity source code — analysis only
- Does not deploy or interact with contracts on-chain
- Does not run `forge script` or execute transactions
- Does not replace individual agent runs — use agents directly for focused analysis
- Does not include STRIDE or DREAD agents — those are telcoin-network specific, not generic Solidity
