# tn-bug-scan Refinement Suggestions

_Created: 2026-04-24 — initial release, no postmortems yet._

This file mirrors `skills/nemesis-scan/suggestions.md` in purpose: a running log of refinements, known gaps, and flow-trace results that accumulate after real runs.

## Intended Use

After each notable run of `/tn-bug-scan`, add a dated section with:

1. **Flow-trace results** — did every phase produce the expected artifacts? Where did context get lost between phases?
2. **Finding quality audit** — were any findings false positives that made it through Phase 6? Were any true positives missed? Which category?
3. **Cache behavior** — did the cache check correctly detect when Phase -1 needed to re-run?
4. **Ticket-format compliance** — did every ticket in `tn-bug-scan-verified.md` include all 10 required fields from `bug-ticket-format.md`?
5. **Domain-skill cross-check** — did Phase 6 correctly load the relevant `tn-domain-*` skill and cite a named invariant?

## Known Gaps at Initial Release

### Activation phrase overlap

The trigger list includes `/tn-bug-scan` as primary. If a future skill reuses similar phrases, activation could become ambiguous. Resolve by keeping the `/tn-bug-scan` prefix distinct from `/tn-nemesis-scan`, `/tn-review`, and `/tn-harden`.

### Duplicated references risk (future)

If a future `tn-bug-scan-light` or similar is created, `references/` may get duplicated. Follow the nemesis-scan lesson: prefer symlinks or a shared `skills/_shared-references/` tree.

### PR-diff default limitations

The default target is `git diff --name-only main...HEAD`. This misses:
- Files affected transitively by the diff (a changed trait impl affects every caller)
- Files that *should* have changed but didn't (missing test coverage for a new branch)

A future enhancement could widen the scope to "direct dependents of changed public interfaces" via `rust-analyzer` or `cargo tree`.

### Phase 4 safety maximum

The feedback loop caps at 3 iterations. Record in the loop summary which findings were still emerging at the cutoff — useful for judging whether to raise the max for complex scopes.

### Verifier skill-loading cost

Phase 6 loads `tn-domain-*` skills via the Skill tool per finding. If many findings touch the same domain, this is wasteful. A future optimization: have the verifier load each relevant skill once at the start of the phase and cache the invariant list in-memory.

### Fork-risk detection heuristics

Fork-risk category patterns (`bug-patterns.md` section 6) are structurally harder to detect than other categories because they require cross-validator reasoning. The recon and mapper heuristics may miss subtle cases. Run at least one scoped test on `crates/tn-reth/src/system_calls.rs` to calibrate detection accuracy.

### Solidity-only scope

When the target scope is Solidity-only (`tn-contracts/src/` changes with no Rust changes), Phase 4 state-check rules adapt to modifier chains and reentrancy windows instead of `.await` boundaries. Ensure the mapper and state-check output explicitly note the mode shift so downstream phases don't search for tokio constructs.

## Planned Evaluation

The success criteria from the design plan will be verified via:

1. **Trigger test** — run `/tn-bug-scan --path crates/consensus/primary/src/aggregators/votes.rs` and confirm:
   - SKILL.md parses args correctly
   - `.audit/bug-domain-patterns.md` is cached after first run
   - All 9 phases produce artifacts in `.audit/tn-bug-scan/`
   - Final reports exist at `.audit/findings/tn-bug-scan-{verified,raw}.md`

2. **Format test** — verify each ticket in `tn-bug-scan-verified.md` has all required fields from `bug-ticket-format.md`.

3. **Reuse test** — confirm Phase 6 verifier correctly loads a `tn-domain-*` skill file to cross-check an invariant.

4. **Comparison test** — run on the same target as `/tn-nemesis-scan` on a known-buggy commit. Confirm tn-bug-scan finds the same bug but frames it as failure-mode/repro (not attack path).

5. **Skill-creator eval pass** — save 2-3 realistic prompts and run the skill-creator eval workflow to get quantitative benchmark and eval-viewer output for iteration.

## Post-Run Template

```markdown
## Run: <date> — <short description of target>

### Scope
- Target: <path/glob>
- Git hash: <short>
- Loop iterations: <N>
- Verified findings: <CRITICAL/HIGH/MEDIUM/LOW counts>

### What worked
- ...

### What didn't work
- ...

### Ticket-format compliance
- ...

### Cache behavior
- ...

### Action items
- ...
```
