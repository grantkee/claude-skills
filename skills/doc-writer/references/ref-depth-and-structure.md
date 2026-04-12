# Depth, structure, and drafting guidance

Used by the drafting agent (Wave 0). Read `tech-doc-rules.md` first.

## Depth vs. redundancy

These are different problems. Confusing them ruins writing in opposite directions.

**Redundancy** is saying the same thing twice in different words, padding lists to three items when you have two points, or adding a conclusion that restates the introduction. Cut it.

**Depth** is explaining how something works, why a decision was made, what the tradeoffs are, or what happens in edge cases. Keep it. This is where writing provides value.

The question is never "is this too long?" It is "does every paragraph tell the reader something new?" A 200-word answer can be redundant. A 2000-word answer can be lean. Match the length to the complexity of the topic and the needs of the reader.

When you catch yourself trimming a useful explanation just to be concise, stop. When you catch yourself repeating a point with different adjectives, cut.

## Document structure

Write top-down. Start with what matters to the reader, not with background they already have.

Standard structure for technical documentation (adapt to fit the document type):

1. **Overview**: one to three sentences on what this thing is and why it exists.
2. **Architecture or design**: how the parts fit together. Diagrams if they help.
3. **Usage**: how to use it. Commands, API calls, configuration.
4. **API or interface reference**: detailed per-function or per-endpoint docs if applicable.
5. **Examples**: concrete, runnable examples that demonstrate common use cases.

Not every document needs all five sections. A crate README may need only overview and usage. An architecture doc may skip examples. Use the sections the reader needs.

## Writing principles

- Active voice. Short sentences when a short sentence will do, longer sentences when the idea needs room.
- One test governs every word: does this word earn its place? If it tells the reader something they need to know, keep it. If it is filler, cut it.
- Value per word, not minimum words. A thorough explanation of a complex topic earns every word. A padded sentence full of qualifiers earns none.
- Your job is to move information into the reader's head with minimal friction. You are not performing intelligence, thoroughness, or brevity. Write at the length the topic demands.
