---
name: gh-issue
description: Generate two markdown files for the current branch — a focused GitHub issue (Problem/Solution) and a broad PR comment summarizing all changes. Use this skill when the user says "create an issue", "write an issue", "gh issue", "draft issue", "issue for this branch", or asks for documentation of what a branch solves. Also trigger when the user wants to describe their branch changes for reviewers, or needs to create context for a PR. Do not trigger for actually posting issues to GitHub via the API — this skill creates local markdown files only.
---

# gh-issue

Generate two local markdown files for the current branch:

1. **`issue.md`** — A focused GitHub issue describing the core problem the branch solves and the high-level approach. Narrow scope: one problem, one solution.
2. **`comment.md`** — A concise PR comment: 1–3 sentences on what changed and why.

These serve different audiences at different moments. The issue is read before the code — it frames the "why" for maintainers and security researchers evaluating the PR. The comment is read alongside the diff — it gives reviewers a quick summary of what changed and why, not a file-by-file inventory.

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

The comment is a short summary a reviewer reads before or alongside the diff. Keep it tight — the diff speaks for itself.

```markdown
# [Concise title]

[1–3 sentences: what changed and why.]

[Optional: link related issues, EIPs, or include benchmark numbers for perf changes.]
```

**Do:**

- Write 1–3 sentences summarizing the change
- Explain why if the diff doesn't make it obvious
- Link related issues or EIPs
- Include benchmark numbers for perf changes

**Don't:**

- List every file changed — that's what the diff is for
- Repeat the title in the body
- Add "Files changed" or "Changes" sections
- Write walls of text that go stale when the diff is updated
- Use filler like "This PR introduces...", "comprehensive", "robust", "enhance", "leverage"

### Step 5: Save the files

- **Issue file**: `issue.md` in the project root.
- **Comment file**: `comment.md` in the project root.

### Step 6: Present the results

Show the user the full contents of both files so they can review inline. Mention both file paths.
