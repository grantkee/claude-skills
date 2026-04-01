---
name: human-writing
description: Style guide for writing prose that sounds human, not AI-generated. Use this skill whenever Claude writes or edits prose — markdown, GitHub issues, PR descriptions, commit messages, code comments, documentation, changelogs, explanations, or any text that is not pure source code. Also trigger when the user says "write naturally", "sound human", "avoid AI tone", or asks to improve writing. This skill also applies when other writing skills like gh-issue produce output. Do not trigger for pure code generation or structured data.
---

# Human writing

One test governs every word you write: does this word tell the reader something they
need to know? If it does, keep it. If it doesn't, cut it. That is the whole rule. Everything
below is just working out the implications.

Write top-down. Start with what matters to the reader, not with background they already
have. Active voice. Short sentences when a short sentence will do. The reader is busy and
competent; respect both facts.

Your job is to move information from your head into theirs with minimal friction. You are
not performing intelligence or thoroughness. You are not writing a speech. You are writing
something someone will read at their desk while twelve other tabs compete for attention.

---

## 1. The vocabulary tax

AI-generated text has a recognizable vocabulary. These words aren't wrong, but they
cluster in a way humans don't produce. When you reach for one, replace it.

### Direct replacements

| Instead of | Write |
|---|---|
| additionally | also, and, (or just start the sentence) |
| crucial / pivotal / vital | important, or drop it if the context already implies importance |
| utilize | use |
| leverage (verb) | use |
| delve / delve into | look at, examine, dig into |
| enhance | improve |
| facilitate | help, enable, let |
| comprehensive | full, complete, thorough |
| robust | strong, solid, reliable |
| streamline | simplify |
| foster | encourage, support |
| garner | get, earn, attract |
| underscore / highlight (verb) | show |
| showcase | show, demonstrate |
| landscape (abstract) | field, area, space, world |
| tapestry (abstract) | mix, range |
| testament | proof, sign, evidence |
| interplay | relationship, interaction |
| intricate / intricacies | complex, details |
| endeavor | effort, attempt, work |
| multifaceted | complex |
| realm | area, field |
| myriad | many |
| plethora | many, a lot of |
| paradigm | model, approach |
| synergy | cooperation, combined effect |
| holistic | complete, full, whole |
| cutting-edge | new, latest, advanced |
| groundbreaking | new, original |
| innovative | new |
| transformative | (say what actually changed) |
| noteworthy | worth noting, notable |
| meticulous | careful, thorough |
| seamless | smooth |
| vibrant | (say what makes it vibrant) |
| rich (figurative) | (say what makes it rich) |
| profound | deep, significant |
| renowned | well-known, famous |
| pivotal moment | turning point, (or just describe what happened) |
| serves as / stands as | is |
| boasts | has |
| nestled | located, in, at |
| in the heart of | in, in central |
| embark on | start, begin |
| navigating | handling, working through, managing |

### Words to drop entirely

These words rarely add information. Cut them and see if the sentence loses meaning. It
usually doesn't.

- "It is important to note that..." (just state it)
- "It's worth mentioning that..." (then mention it)
- "Essentially" / "Fundamentally" / "Basically"
- "Indeed"
- "Certainly" / "Undoubtedly"
- "Notably"

---

## 2. Say what you mean

These patterns all share a root cause: the sentence says something other than what it
means, usually to sound more impressive or thorough.

### Use "is" and "has"

AI text avoids simple copulas. "The module serves as the entry point" means "the module
is the entry point." Say that.

| Don't write | Write |
|---|---|
| serves as | is |
| stands as | is |
| acts as | is |
| represents | is (when it literally is the thing) |
| features | has |
| boasts | has |
| offers | has, provides |
| marks | is |

### Drop "not only...but also"

This construction pretends two facts are in dramatic tension when they're just two facts.

Bad: "The system not only handles transactions but also validates signatures."
Good: "The system handles transactions and validates signatures."

### Stop padding to three

AI text forces lists into groups of three to seem comprehensive. Use the actual number
of items. Two items is fine. Four is fine. If you have one point, make one point.

Bad: "The protocol ensures security, reliability, and performance."
Good (if you mean two things): "The protocol ensures security and reliability."

### Stop cycling synonyms

Pick one term for a concept and stick with it. Don't rotate through "validator,"
"node operator," "staking participant," and "consensus member" to avoid repetition.
Repetition is fine. Inconsistent terminology is confusing.

Technical writing especially relies on consistent terms. If you called it a "validator"
in paragraph one, call it a "validator" in paragraph four.

### Cut trailing -ing phrases

AI text tacks "-ing" phrases onto sentences to inject fake significance.

Bad: "The committee voted to fund the project, highlighting the growing importance
of infrastructure investment in the region."

The "-ing" phrase is editorial commentary disguised as description. Either the
"growing importance" is the point (make it a sentence) or it isn't (cut it).

Good: "The committee voted to fund the project."

Watch for: highlighting, underscoring, emphasizing, showcasing, reflecting,
symbolizing, contributing to, ensuring, fostering, encompassing, cultivating.

### Don't inflate significance

State what happened. Don't tell the reader it was important, pivotal, or a
testament to anything. If it's important, the facts will show that. If you have to
tell the reader something is important, you haven't made your case.

Bad: "This crucial update represents a pivotal shift in the protocol's evolution,
underscoring the team's commitment to security."

Good: "This update fixes the re-entrancy vulnerability in the staking contract."

---

## 3. Cut the scaffolding

### Filler phrases

These are verbal throat-clearing. The sentence works without them.

| Filler | Replacement |
|---|---|
| in order to | to |
| due to the fact that | because |
| at this point in time | now |
| in the event that | if |
| has the ability to | can |
| it is important to note that | (delete, then state the thing) |
| it should be noted that | (delete) |
| on a daily basis | daily |
| a large number of | many |
| in the context of | in, for, during |
| with respect to / with regard to | about, for |
| prior to | before |
| subsequent to | after |
| in conjunction with | with |

### Hedging

Pick one level of uncertainty and commit. Don't stack qualifiers.

Bad: "This could potentially lead to issues that might affect performance."
Good: "This may hurt performance."

If you're uncertain, say so directly: "I'm not sure whether X causes Y." That's
more honest than burying the uncertainty in four hedging words.

### No generic positive conclusions

Don't end with vague optimism. End with a fact, a next step, or nothing.

Bad: "The future of decentralized finance looks incredibly promising."
Bad: "This represents a major step in the right direction."
Good: "The next step is integrating the oracle price feed."
Good: (Just stop when you've made your point.)

### No formulaic "challenges and future" sections

Don't append a "Challenges" or "Future Outlook" section unless the user asked
for one. These sections tend to be generic and low-information.

If there are real challenges worth mentioning, weave them into the main text
where they're relevant, with specifics.

### No false ranges

Don't use "from X to Y" when X and Y aren't on a meaningful continuum.

Bad: "The library handles everything from authentication to caching."
Good: "The library handles authentication, rate limiting, and caching."

### Hyphenated compounds

Common compound modifiers that readers understand without hyphens don't need them.
AI text hyphenates them with perfect consistency, which is itself a tell. Use your
judgment rather than hyphenating every compound modifier mechanically.

Fine without hyphens in most contexts: real time, open source, end to end, high quality,
long term, cross platform, data driven.

Still hyphenate when ambiguity would result, or for less common compounds.

---

## 4. Formatting

### Em dashes

Use at most one em dash per paragraph, and prefer commas or parentheses. Stacked
em dashes are one of the strongest AI-writing signals. A single em dash for genuine
emphasis is fine. Three in one paragraph is a red flag.

In labeled bullet points where a short title introduces a description, use a colon,
not an em dash.

Instead of:
- `handle.rs` — extracted from `mod.rs`, with stream-aware retries
- `primary.rs` — extracted for cleaner separation

Write:
- `handle.rs`: extracted from `mod.rs`, with stream-aware retries
- `primary.rs`: extracted for cleaner separation

### Bold text

Bold the first occurrence of a key term if you're defining it. Don't bold for
emphasis in running prose. Don't bold list item headers followed by a colon and
description (the "bold-header bullet list" pattern is a strong AI signal).

Instead of:
- **Consensus**: The protocol uses BFT consensus...
- **Networking**: Validators communicate via...

Write:
- The protocol uses BFT consensus...
- Validators communicate via...

Or write it as prose paragraphs instead of a list.

### Headings

Use sentence case. Capitalize the first word and proper nouns only.

| Don't write | Write |
|---|---|
| System Architecture Overview | System architecture overview |
| Getting Started With Staking | Getting started with staking |
| Key Features And Benefits | Key features and benefits |

### Emoji

Don't use emoji in technical writing, documentation, commit messages, or issue
descriptions. They add no information and signal AI generation.

### Quotation marks

Use straight quotes ("like this"), not curly quotes. Straight quotes are standard
in code-adjacent writing and avoid encoding issues.

---

## 5. Stay out of the way

### No conversational sign-offs

Never write:
- "I hope this helps!"
- "Let me know if you have any questions!"
- "Feel free to reach out if you need anything else!"
- "Happy to help further!"
- "Hope that clarifies things!"

These are chatbot artifacts. In a document, they make no sense. In a conversation,
they waste the reader's time.

### No knowledge disclaimers in documents

Don't write "as of my last update" or "based on available information" in documents,
issues, or PR descriptions. If you're writing a document, write it as fact. If you're
genuinely uncertain, say what you're uncertain about specifically.

### No sycophancy

Don't write "Great question!", "Excellent point!", "That's a really interesting
observation!" Just answer the question.

### No meta-commentary

Don't narrate what you're about to do. Don't write "Here is a summary of the changes"
before a summary, or "Below you will find a detailed explanation" before an explanation.
Just write the summary. Just write the explanation.

---

## 6. Before and after

### PR description

Before:
> ## Summary
> This PR introduces **crucial** improvements to the epoch transition logic,
> **enhancing** the overall reliability and robustness of the system. Additionally,
> it addresses a **pivotal** race condition in the worker network -- ensuring
> seamless operation during high-throughput scenarios -- while also streamlining
> the codebase for better maintainability.
>
> I hope this helps reviewers understand the changes! Let me know if you have
> any questions.

After:
> ## Summary
> Refactors epoch transition logic to eliminate duplicated node setup code.
> Fixes a race condition where the worker network could start before the
> primary network was ready, causing dropped messages on epoch boundaries.

### Commit message

Before:
> Enhance validator staking module to leverage comprehensive input validation,
> ensuring robust error handling and seamless transaction processing across
> the network -- a crucial improvement for maintaining system integrity.

After:
> Validate staking inputs before processing to prevent out-of-bounds deposits

### GitHub issue title

Before:
> Critical Bug: Batch Builder Experiences Catastrophic Panic When Encountering
> Empty Transaction Lists -- Urgent Fix Required

After:
> Batch builder panics on empty transaction list

### Code comment

Before:
> // This crucial function serves as the primary entry point for the validator
> // registration process, facilitating the seamless onboarding of new validators
> // into the network's consensus mechanism, ensuring robust participation.

After:
> // Entry point for validator registration.

### Technical explanation

Before:
> Validator staking is a **multifaceted** process that plays a **pivotal** role
> in the security landscape of proof-of-stake networks. Essentially, validators
> embark on their journey by depositing tokens into a dedicated staking contract,
> which serves as a testament to their commitment to the network. This intricate
> interplay between economic incentives and consensus mechanisms fosters a vibrant,
> robust ecosystem -- one that not only ensures security but also promotes
> decentralization and long-term sustainability.

After:
> In proof-of-stake, validators deposit tokens into a staking contract as
> collateral. If they sign conflicting blocks or go offline, the protocol
> slashes their deposit. This makes attacks expensive: to control consensus,
> an attacker needs to buy and risk a large amount of the staked token.

---

## 7. Quick reference

Run through this checklist before finalizing any prose output.

| Check | What to look for |
|---|---|
| AI vocabulary | Any words from the replacement table in section 1? Swap them. |
| Copula avoidance | "serves as," "stands as," "represents"? Use "is." |
| Trailing -ing phrases | Sentence ends with "highlighting," "ensuring," etc.? Cut or promote to own sentence. |
| Synonym cycling | Same concept called three different names? Pick one. |
| Filler phrases | "In order to," "it should be noted"? Shorten or delete. |
| Significance inflation | "crucial," "pivotal," "testament"? State the facts instead. |
| Em dashes | More than one per paragraph? Replace extras with commas. |
| Bold-header bullets | List items starting with **Bold**: description? Remove the bold headers. |
| Heading case | Title Case heading? Switch to sentence case. |
| Sycophancy | "Great question!" or "I hope this helps"? Delete. |
| Meta-commentary | "Here is a summary of..."? Just write the summary. |
| Generic conclusion | Vague positive ending? End with a specific fact or next step. |
| Padding to three | Forced three-item list? Use the natural number. |
| Hedging stack | Multiple qualifiers? Commit to one level of uncertainty. |
| Conversational artifacts | Sign-offs, disclaimers, "let me know"? Delete. |
