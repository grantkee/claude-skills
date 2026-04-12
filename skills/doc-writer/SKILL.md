---
name: doc-writer
description: |
  Sequential editing pipeline for technical documentation. Decomposes human-writing
  guidelines into focused single-pass agents that each apply one narrow set of rules.
  Works for any professional technical documentation: architecture docs, READMEs,
  crate docs, guides, changelogs.
  Trigger on: "doc-writer", "edit docs", "polish docs", "run doc pipeline",
  "clean up this document", "make this sound human"
---

# Doc-writer

Sequential editing pipeline that decomposes prose quality rules into focused single-pass agents. Each agent loads only its relevant rules, makes minimal surgical edits, and passes the file to the next wave.

## Input

- **file_path**: path to the document to write or edit (required)
- **--edit-only**: skip Wave 0 (drafting) and start at Wave 1. Use when the document already exists and needs editing only.
- **outline**: for Wave 0, a description of what to write (topic, audience, scope). Ignored if `--edit-only`.

## Wave pipeline

Waves run strictly in sequence. Each agent edits the file in place; the next agent reads the updated version.

### Wave 0: Draft (skip if --edit-only)

Spawn an agent (model: opus) to write the initial document.

```
Agent({
  model: "opus",
  description: "Draft technical document",
  prompt: "You are a technical writer drafting documentation.

Read these reference files FIRST:
- skills/doc-writer/references/tech-doc-rules.md
- skills/doc-writer/references/ref-depth-and-structure.md

YOUR TASK: Write a document at {file_path} based on this outline:
{outline}

Follow the structure and depth guidance in ref-depth-and-structure.md. Follow the shared
constraints in tech-doc-rules.md. Write at the length the topic demands — no padding,
no artificial brevity. The reader is a developer."
})
```

### Wave 1: Vocabulary

Spawn an agent (model: sonnet) for mechanical word replacement.

```
Agent({
  model: "sonnet",
  description: "Vocabulary pass",
  prompt: "You are an editor making a single focused pass over technical documentation.
YOUR SOLE CONCERN: replacing AI vocabulary with plain alternatives.

Read these reference files FIRST:
- skills/doc-writer/references/tech-doc-rules.md
- skills/doc-writer/references/ref-vocabulary.md

Then read the target file: {file_path}

Apply ONLY the replacement table and drop-list from ref-vocabulary.md. Scan every sentence.
Replace matches. Do not make any other changes. Edit the file in place.
Report the number of replacements made."
})
```

### Wave 2: Directness

```
Agent({
  model: "sonnet",
  description: "Directness pass",
  prompt: "You are an editor making a single focused pass over technical documentation.
YOUR SOLE CONCERN: fixing indirect language patterns.

Read these reference files FIRST:
- skills/doc-writer/references/tech-doc-rules.md
- skills/doc-writer/references/ref-directness.md

Then read the target file: {file_path}

Apply ONLY the six rules from ref-directness.md: copula avoidance, not-only-but-also,
padding to three, synonym cycling, trailing -ing phrases, significance inflation.
Do not make any other changes. Edit the file in place.
Report the number of changes made and which rules drove them."
})
```

### Wave 3: Scaffolding

```
Agent({
  model: "sonnet",
  description: "Scaffolding pass",
  prompt: "You are an editor making a single focused pass over technical documentation.
YOUR SOLE CONCERN: cutting filler and structural padding.

Read these reference files FIRST:
- skills/doc-writer/references/tech-doc-rules.md
- skills/doc-writer/references/ref-scaffolding.md

Then read the target file: {file_path}

Apply ONLY the six rules from ref-scaffolding.md: filler phrases, hedging, generic
conclusions, formulaic sections, false ranges, hyphenated compounds.
Do not make any other changes. Edit the file in place.
Report the number of changes made and which rules drove them."
})
```

### Wave 4: Formatting

```
Agent({
  model: "sonnet",
  description: "Formatting pass",
  prompt: "You are an editor making a single focused pass over technical documentation.
YOUR SOLE CONCERN: fixing formatting patterns.

Read these reference files FIRST:
- skills/doc-writer/references/tech-doc-rules.md
- skills/doc-writer/references/ref-formatting.md

Then read the target file: {file_path}

Apply ONLY the five rules from ref-formatting.md: em dashes, bold text, heading case,
emoji, quotation marks. Do not change wording or meaning.
Edit the file in place. Report the number of changes made and which rules drove them."
})
```

### Wave 5: Cleanup

```
Agent({
  model: "sonnet",
  description: "Cleanup pass",
  prompt: "You are an editor making a single focused pass over technical documentation.
YOUR SOLE CONCERN: removing conversational artifacts.

Read these reference files FIRST:
- skills/doc-writer/references/tech-doc-rules.md
- skills/doc-writer/references/ref-cleanup.md

Then read the target file: {file_path}

Apply ONLY the four rules from ref-cleanup.md: conversational sign-offs, knowledge
disclaimers, sycophancy, meta-commentary. Do not make any other changes.
Edit the file in place. Report the number of changes made and which rules drove them."
})
```

### Wave 6: Review

```
Agent({
  model: "sonnet",
  description: "Review pass",
  prompt: "You are a reviewer checking technical documentation against a quality checklist.
YOU DO NOT EDIT THE FILE. You read it and report pass/fail.

Read these reference files FIRST:
- skills/doc-writer/references/tech-doc-rules.md
- skills/doc-writer/references/ref-checklist.md

Then read the target file: {file_path}

Check every item in the checklist from ref-checklist.md. For each failing check, cite the
line number and problematic text. Use the report format specified in ref-checklist.md.
End with which waves (if any) need to be re-run."
})
```

**Retry logic**: if Wave 6 reports failures, re-run only the specific failing wave(s) once, then re-run Wave 6. If failures persist after one retry, report them to the user for manual review.

### Wave 7: Format output

Spawn the existing `format-output` agent with the file path. This agent applies file-specific mechanical formatting (sentence-per-line in READMEs, etc.) without changing wording.
