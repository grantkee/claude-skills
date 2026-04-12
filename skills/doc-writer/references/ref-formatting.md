# Formatting pass

Used by the formatting agent (Wave 4). Read `tech-doc-rules.md` first.

Your sole job: fix formatting issues using the five rules below. Do not change wording or meaning.

## 1. Em dashes

Use at most one em dash per paragraph, and prefer commas or parentheses. Stacked em dashes are one of the strongest AI-writing signals. A single em dash for genuine emphasis is fine. Three in one paragraph is a red flag.

In labeled bullet points where a short title introduces a description, use a colon, not an em dash.

Instead of:
- `handle.rs` — extracted from `mod.rs`, with stream-aware retries
- `primary.rs` — extracted for cleaner separation

Write:
- `handle.rs`: extracted from `mod.rs`, with stream-aware retries
- `primary.rs`: extracted for cleaner separation

## 2. Bold text

Bold the first occurrence of a key term if you are defining it. Do not bold for emphasis in running prose. Do not bold list item headers followed by a colon and description (the "bold-header bullet list" pattern is a strong AI signal).

Instead of:
- **Consensus**: The protocol uses BFT consensus...
- **Networking**: Validators communicate via...

Write:
- The protocol uses BFT consensus...
- Validators communicate via...

Or write it as prose paragraphs instead of a list.

## 3. Headings

Use sentence case. Capitalize the first word and proper nouns only.

| Do not write | Write |
|---|---|
| System Architecture Overview | System architecture overview |
| Getting Started With Staking | Getting started with staking |
| Key Features And Benefits | Key features and benefits |

## 4. Emoji

Do not use emoji in technical writing, documentation, commit messages, or issue descriptions. They add no information and signal AI generation.

## 5. Quotation marks

Use straight quotes ("like this"), not curly quotes. Straight quotes are standard in code-adjacent writing and avoid encoding issues.
