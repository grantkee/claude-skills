---
name: tn-nemesis-scan
description: "Deep combined audit using iterative Feynman + State Inconsistency analysis across 8 phases with specialized agents. Language-agnostic. Spawns nemesis-orchestrator which coordinates recon, mapping, interrogation, state checking, feedback loop, journey tracing, verification, and reporting. Triggers on /nemesis-scan or deep combined audit."
---

# Nemesis Scan

Deep combined Feynman + State Inconsistency audit orchestrated across 8 specialized agents.

## Activation

- User says `/nemesis-scan` or `nemesis scan` or `deep combined audit`
- User wants maximum-depth business logic + state inconsistency coverage

## Execution

1. Determine the target scope from the user's request (files, directories, or modules to audit)
2. Create the output directory:
   ```bash
   mkdir -p .audit/nemesis-scan .audit/findings
   ```
3. Resolve the path to this skill's `references/` directory for agent prompts
4. Spawn the `nemesis-orchestrator` agent:

```
Agent({
  subagent_type: "nemesis-orchestrator",
  description: "Run nemesis-scan pipeline",
  prompt: "Run the full nemesis-scan pipeline on the following target scope:

Target: [target files/directories]

References are at: [absolute path to skills/tn-nemesis-scan/references/]

Execute all 8 phases in order:
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

5. After the orchestrator returns, relay its summary to the user with paths to the report files.
