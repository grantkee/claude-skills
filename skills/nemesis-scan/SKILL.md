---
name: nemesis-scan
description: "Deep combined audit using iterative Feynman + State Inconsistency analysis across 8 phases with specialized agents. Language-agnostic. Dynamically discovers domain-specific patterns via Phase -1 before the main pipeline. Spawns nemesis-orchestrator which coordinates domain discovery, recon, mapping, interrogation, state checking, feedback loop, journey tracing, verification, and reporting. Triggers on /nemesis-scan or deep combined audit."
---

# Nemesis Scan

Deep combined Feynman + State Inconsistency audit orchestrated across 8 specialized agents, with dynamic domain pattern discovery.

## Activation

- User says `/nemesis-scan` or `nemesis scan` or `deep combined audit`
- User wants maximum-depth business logic + state inconsistency coverage

## Invocation Format

```
/nemesis-scan [target] [optional: --hints "domain description"] [optional: --fresh]
```

Examples:
- `/nemesis-scan src/contracts/` — audit contracts, auto-discover domain
- `/nemesis-scan src/consensus/ --hints "DAG-based BFT consensus"` — audit with domain hints
- `/nemesis-scan src/ --fresh` — force domain pattern regeneration

## Execution

1. Determine the target scope from the user's request (files, directories, or modules to audit)

2. Parse optional arguments:
   - **Domain hints:** Extract text after `--hints` (quoted string). If absent, set to `"none"`.
   - **Fresh flag:** If `--fresh` is present, skip cache check and force domain discovery.

3. Create the output directory:
   ```bash
   mkdir -p .audit/nemesis-scan/research .audit/findings
   ```

4. **Cache check** — determine if domain discovery is needed:
   ```bash
   # Check if cached domain-patterns exist
   if [ -f .audit/domain-patterns.md ]; then
     head -5 .audit/domain-patterns.md
   fi
   ```
   
   Read the header of `.audit/domain-patterns.md` if it exists. The cache is **valid** when ALL of:
   - The file exists
   - The `_Git hash:_` line matches current `git rev-parse --short HEAD`
   - The `_Target scope:_` line matches the requested scope
   - The `_User hints:_` line matches the provided hints
   - The `--fresh` flag was NOT passed
   
   Set `discovery_needed = true` if cache is invalid or missing. Set `discovery_needed = false` if cache is valid.

5. Resolve the path to this skill's `references/` directory for agent prompts.

6. Spawn the `nemesis-orchestrator` agent:

```
Agent({
  subagent_type: "nemesis-orchestrator",
  description: "Run nemesis-scan pipeline",
  prompt: "Run the full nemesis-scan pipeline on the following target scope:

Target: [target files/directories]
Domain hints: [user hints or 'none']
Discovery needed: [true/false]

References are at: [absolute path to skills/nemesis-scan/references/]

All agents MUST read core-rules.md and language-adaptation.md.

[If discovery_needed is true:]
Run Phase -1 (Domain Discovery) FIRST:
- Phase -1a: Spawn nemesis-strategy with project-context, target scope, hints, and research-guide.md
- Phase -1b: Spawn parallel nemesis-researcher agents (one per research topic from strategy plan)
- Phase -1c: Compile fragments into .audit/domain-patterns.md with cache metadata

[If discovery_needed is false:]
Skip Phase -1. Domain patterns are cached at .audit/domain-patterns.md

Then execute all 8 phases in order, with all agents reading .audit/domain-patterns.md for domain context:
- Phase 0+1 (parallel): nemesis-recon + nemesis-mapper
- Phase 2: nemesis-feynman (full mode)
- Phase 3: nemesis-state-check (full mode)
- Phase 4: feedback loop (max 3 iterations)
- Phase 5: nemesis-journey
- Phase 6: nemesis-verifier
- Phase 7: nemesis-reporter

Write phase outputs to .audit/nemesis-scan/
Write final reports to .audit/findings/nemesis-scan-verified.md and .audit/findings/nemesis-scan-raw.md

Present a concise summary when complete."
})
```

7. After the orchestrator returns, relay its summary to the user with paths to the report files.
