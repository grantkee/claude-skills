# Review checklist

Used by the review agent (Wave 6). Read `tech-doc-rules.md` first.

You are NOT an editor. Do NOT change the file. Read it and report pass/fail for each check below. For each failure, cite the specific line number and the problematic text.

## Checklist

| # | Check | What to look for |
|---|---|---|
| 1 | Depth vs. redundancy | Did the document cut something the reader needs? Does it repeat something the reader already knows? |
| 2 | AI vocabulary | Any words from the replacement table? (crucial, pivotal, leverage, utilize, delve, enhance, robust, seamless, comprehensive, foster, garner, underscore, showcase, landscape, tapestry, testament, interplay, intricate, endeavor, multifaceted, realm, myriad, plethora, paradigm, synergy, holistic, cutting-edge, groundbreaking, innovative, transformative, meticulous, vibrant, profound, renowned, embark, navigating) |
| 3 | Copula avoidance | "serves as," "stands as," "acts as," "represents" used where "is" works? |
| 4 | Trailing -ing phrases | Sentences ending with "highlighting," "ensuring," "showcasing," etc.? |
| 5 | Synonym cycling | Same concept called different names in different paragraphs? |
| 6 | Filler phrases | "In order to," "it should be noted," "due to the fact that," etc.? |
| 7 | Significance inflation | "crucial," "pivotal," "testament"? State facts instead. |
| 8 | Em dashes | More than one per paragraph? |
| 9 | Bold-header bullets | List items starting with **Bold**: description? |
| 10 | Heading case | Any Title Case headings? Should be sentence case. |
| 11 | Sycophancy | "Great question!" or "I hope this helps"? |
| 12 | Meta-commentary | "Here is a summary of..."? |
| 13 | Generic conclusion | Vague positive ending? |
| 14 | Padding to three | Forced three-item list where fewer items are meant? |
| 15 | Hedging stack | Multiple qualifiers in one sentence? |
| 16 | Conversational artifacts | Sign-offs, disclaimers, "let me know"? |

## Report format

```
## Review results

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Depth vs. redundancy | PASS / FAIL | [line numbers and details if FAIL] |
| 2 | AI vocabulary | PASS / FAIL | [specific words found if FAIL] |
...

Failing waves: [list which waves need re-run, e.g., "Wave 1 (vocabulary), Wave 4 (formatting)"]
```

If all checks pass, report "All checks pass. No re-runs needed."
