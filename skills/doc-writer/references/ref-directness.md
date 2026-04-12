# Directness pass

Used by the directness agent (Wave 2). Read `tech-doc-rules.md` first.

Your sole job: fix the six patterns below. Do not make any other changes.

## 1. Use "is" and "has"

AI text avoids simple copulas. "The module serves as the entry point" means "the module is the entry point." Say that.

| Do not write | Write |
|---|---|
| serves as | is |
| stands as | is |
| acts as | is |
| represents | is (when it literally is the thing) |
| features | has |
| boasts | has |
| offers | has, provides |
| marks | is |

## 2. Drop "not only...but also"

This construction pretends two facts are in dramatic tension when they are just two facts.

Bad: "The system not only handles transactions but also validates signatures."
Good: "The system handles transactions and validates signatures."

## 3. Stop padding to three

AI text forces lists into groups of three. Use the actual number of items. Two items is fine. Four is fine. If you have one point, make one point.

Bad: "The protocol ensures security, reliability, and performance." (if only two things are meant)
Good: "The protocol ensures security and reliability."

## 4. Stop cycling synonyms

Pick one term for a concept and stick with it. Do not rotate through "validator," "node operator," "staking participant," and "consensus member" to avoid repetition. Repetition is fine. Inconsistent terminology is confusing.

If the document called it a "validator" in paragraph one, call it a "validator" in paragraph four.

## 5. Cut trailing -ing phrases

AI text tacks "-ing" phrases onto sentences to inject fake significance.

Bad: "The committee voted to fund the project, highlighting the growing importance of infrastructure investment in the region."

The "-ing" phrase is editorial commentary disguised as description. Either the "growing importance" is the point (make it a sentence) or it is not (cut it).

Good: "The committee voted to fund the project."

Watchlist: highlighting, underscoring, emphasizing, showcasing, reflecting, symbolizing, contributing to, ensuring, fostering, encompassing, cultivating.

## 6. Do not inflate significance

State what happened. Do not tell the reader it was important, pivotal, or a testament to anything. If it is important, the facts show that.

Bad: "This crucial update represents a pivotal shift in the protocol's evolution, underscoring the team's commitment to security."
Good: "This update fixes the re-entrancy vulnerability in the staking contract."
