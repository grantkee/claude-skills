---
name: gh-issue
description: Generate two markdown files for the current branch — a focused GitHub issue (Problem/Solution) and a broad PR comment summarizing all changes. Use this skill when the user says "create an issue", "write an issue", "gh issue", "draft issue", "issue for this branch", or asks for documentation of what a branch solves. Also trigger when the user wants to describe their branch changes for reviewers, or needs to create context for a PR. Do not trigger for actually posting issues to GitHub via the API — this skill creates local markdown files only.
---

# gh-issue

Generate two local markdown files for the current branch:

1. **`issue.md`** — A focused GitHub issue describing the core problem the branch solves and the high-level approach. Narrow scope: one problem, one solution.
2. **`comment.md`** — A comprehensive PR comment summarizing everything the branch touches. Broad scope: every meaningful change gets a mention.

These serve different audiences at different moments. The issue is read before the code — it frames the "why" for maintainers and security researchers evaluating the PR. The comment is read alongside the code — it orients reviewers to the full scope of changes so nothing gets overlooked.

## Process

### Step 1: Gather branch context

Run these in parallel to understand the branch:

1. **Identify the base branch** — check if `main` or `master` exists, or use the most likely upstream branch.
2. **Get the full diff** — `git diff <base>...HEAD` to see all changes on this branch.
3. **Read commit messages** — `git log <base>..HEAD --oneline` for the commit history on this branch.
4. **Get the branch name** — `git branch --show-current` since the branch name often hints at intent.

### Step 2: Analyze the changes

Read through the diff and commits to understand:

- **What changed**: which files, modules, or components were touched
- **The primary motivation**: what single problem or need is the branch named after? This becomes the issue.
- **Everything else**: what other changes ride along — refactors, cleanups, dependency updates, test additions? These go in the comment.
- **What category each change falls into**: new feature, bug fix, security patch, refactor, configuration change, dependency update, etc.
- **What's at stake**: what happens if the primary problem isn't addressed? For bugs: what breaks. For features: what's missing. For security: what's the risk.

### Step 3: Write the issue file (`issue.md`)

The issue covers only the primary problem the branch addresses — the thing the branch is named after. If the branch adds a basefee contract, the issue is about the need for a basefee contract. If it fixes a validator timeout, the issue is about the timeout bug. Everything else belongs in the comment.

```markdown
# [Concise title describing the problem or need]

## Problem

[2-4 paragraphs describing the problem, need, or context. Be specific about what's wrong, missing, or needed. Include:

- What the current behavior or state is
- Why it's problematic or insufficient
- What impact this has (on users, security, functionality, etc.)
- Any relevant background context that helps a reviewer understand the domain]

## Solution

[1-3 paragraphs outlining the proposed approach at a high level. Write as a proposal — what _should_ be done, not what _was_ done. Use prescriptive framing ("introduce X", "X should expose", "X should reject") even though the solution is based on actual code changes. The issue is read before the PR, so it should sound like a recommendation for reviewers to evaluate.

Describe:

- The general strategy for addressing the problem
- Key design decisions and why they were made
- Which components or areas are affected
- Any tradeoffs or considerations

If it helps clarify the approach, include brief pseudocode — but never include actual implementation code. Reviewers will see the real code in the linked PR.]
```

**Issue writing guidelines:**

- **Problem section**: Lead with what's wrong or missing. Be specific enough that a maintainer unfamiliar with the recent work can understand it. For security patches, describe the risk without providing exploit details — give enough for security researchers to assess the fix.
- **Solution section**: Write as a proposal — describe what _should_ happen, not what _has_ happened. Use prescriptive language ("introduce", "should expose", "should reject") rather than past-tense or present-tense descriptions of completed work ("exposes", "is deployed", "was added"). The content should still be informed by the actual code changes — you're describing the same approach, just framed as a recommendation rather than a changelog. This matters because the issue is meant to be read _before_ the PR, as context for evaluating whether the approach is sound.
- **No code**: Describe the approach in plain language. Focus on "what" and "why", not "how" at a code level. Mention affected components so reviewers know where to look. Never paste actual code from the diff.
- **Tone**: Succinct, scannable in under 2 minutes. Precise technical language. Every sentence earns its place.

### Step 4: Write the PR comment file (`comment.md`)

The comment covers the full scope of the branch — every meaningful change, grouped logically. This is what a reviewer reads to orient themselves before (or while) reading the diff. It should help them understand what to expect and where to focus attention.

```markdown
# [Branch name or descriptive title]

## Overview

[1-2 sentences summarizing the branch's purpose and scope.]

## Changes

### [Group 1: e.g., "EpochGasTarget contract"]

- [Bullet points describing what changed and why, at a summary level]

### [Group 2: e.g., "ConsensusRegistry improvements"]

- [Bullet points]

### [Group 3: e.g., "Codebase cleanup"]

- [Bullet points]

[Add as many groups as needed to cover all changes. Group by logical area, not by file.]
```

**Comment writing guidelines:**

- **Comprehensive**: mention every meaningful change — new files, modified contracts, removed code, test additions, deployment changes. A reviewer should not be surprised by anything in the diff after reading this.
- **Grouped by area**: organize changes by logical component or theme, not file-by-file. A reviewer reading this should build a mental map of what the branch touches.
- **Brief per item**: each bullet should be 1-2 sentences. Enough to understand what changed and why, not a full explanation.
- **No code**: same rule as the issue — describe changes in words. The diff is right there.
- **Call out removals**: deleted code and removed features deserve explicit mention so reviewers know the absence is intentional.

### Step 5: Save the files

- **Issue file**: `issue.md` in the project root.
- **Comment file**: `comment.md` in the project root.

### Step 6: Present the results

Show the user the full contents of both files so they can review inline. Mention both file paths.
