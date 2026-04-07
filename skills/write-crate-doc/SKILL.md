---
name: write-crate-doc
description: |
  Generate crate-level documentation for telcoin-network crates.
  Trigger on: "document this crate", "write docs", "add rustdoc", "architecture doc", "module docs", "crate docs", "write crate documentation"
---

# Crate Documentation Generator

Generate high-quality crate-level documentation for the telcoin-network repository -- a Rust blockchain node combining Narwhal/Bullshark DAG-based BFT consensus with EVM execution via Reth.

## Project Context

The telcoin-network repo (`tn-4`) is organized as a Cargo workspace with crates spanning consensus, execution, networking, and utilities:

**Consensus layer:**
- `crates/consensus/primary` -- Primary actors (Narwhal/Bullshark DAG consensus)
- `crates/consensus/worker` -- Worker components to create and sync batches
- `crates/consensus/executor` -- Process consensus output and execute every transaction

**Execution layer:**
- `crates/engine` -- Executes consensus output into EVM blocks
- `crates/batch-builder` -- Transaction pool management and batch assembly
- `crates/batch-validator` -- Batch validation logic
- `crates/tn-reth` -- Reth compatibility layer (EVM, precompiles, chain spec)
- `crates/execution/tn-rpc` -- RPC request handling for state sync

**Networking:**
- `crates/network-libp2p` -- libp2p-based p2p networking (gossipsub, request-response, Kademlia, peer management)
- `crates/network-types` -- Network message types

**Infrastructure:**
- `crates/config` -- Node and network configuration, key management
- `crates/storage` -- Persistent storage types
- `crates/state-sync` -- State synchronization for non-committee nodes
- `crates/types` -- Core protocol types
- `crates/node` -- Node orchestration
- `crates/tn-utils` -- Shared utilities

**Testing:**
- `crates/test-utils` -- Test infrastructure
- `crates/test-utils-committee` -- Committee test utilities
- `crates/e2e-tests` -- End-to-end tests

**Binary:**
- `bin/telcoin-network` -- Main binary
- `crates/telcoin-network-cli` -- CLI implementation

The workspace sets `missing_docs = "warn"` globally in `[workspace.lints.rust]`. All crates inherit this lint. Existing crate-level doc comments (`//!`) are terse -- typically 1-3 lines in `lib.rs`. Some crates have README.md files of varying quality. The best documentation in the repo is `crates/tn-reth/src/evm/tel_precompile/README.md`.

Key architectural documents:
- `SYNC.md` (repo root) -- Epoch Chain and Consensus Chain synchronization strategy
- `crates/batch-builder/README.md` -- Detailed batch assembly, pool updates, security model

## Process

### Phase 1: Audit the target crate's documentation state

1. Read the crate's `Cargo.toml` to understand dependencies, features, and lint overrides
2. Read the crate's `lib.rs` to see existing `//!` doc comments and public API surface
3. List all `.rs` source files in the crate to understand module structure
4. Run `cargo doc -p <crate-name> 2>&1 | grep "warning: missing"` to find undocumented public items (use `--no-deps` to skip dependencies)
5. Check if the crate already has a `README.md`
6. Summarize findings: number of public items, percentage documented, module count

### Phase 2: Read and understand the crate's architecture

1. Read every source file in the crate (use subagents for large crates)
2. Identify the crate's role in the overall system using the Project Context above
3. Map module dependencies and data flow within the crate
4. Identify key types, traits, and functions that form the public API
5. Check cross-crate dependencies to understand integration points
6. Read any referenced types/traits from other tn-* crates to understand the interfaces
7. Cross-reference with `SYNC.md` and other design docs if the crate touches consensus or sync

### Phase 3: Generate documentation following the exemplar

Generate the documentation artifacts in this order:

1. **Crate README.md** -- The primary artifact. Follows the exemplar structure (see below). Write this first because it forces you to understand the crate deeply before writing inline docs.
2. **Crate-level doc comments** (`//!` in `lib.rs`) -- A concise summary (3-10 lines) with feature flags if applicable. Should align with README overview.
3. **Module-level doc comments** (`//!` at top of each module file) -- One-liner explaining the module's purpose.
4. **Public item doc comments** (`///` on pub types, traits, functions, methods) -- Focus on items that `cargo doc` warns about. Include `# Examples` sections for non-obvious APIs.

### Phase 4: Verify with cargo doc

1. Run `cargo doc -p <crate-name> --no-deps 2>&1` and confirm warning count decreased
2. Run `cargo test -p <crate-name> --doc` to verify any doc examples compile
3. Review the generated HTML if accessible, or scan the doc output for broken links
4. Check that all cross-references (`[`TypeName`]`) resolve correctly

## Documentation Types

### Crate README.md

The primary documentation artifact. Lives at the crate root (e.g., `crates/engine/README.md`). Follows the exemplar structure below. This is what developers read first when encountering the crate.

### Crate-level doc comments (`//!` in `lib.rs`)

Concise (3-10 lines). First line is a single-sentence summary. Additional lines explain the crate's role and link to the README for details. Include `## Feature Flags` if the crate has non-trivial features.

Example from the repo:
```rust
//! The block builder maintains the transaction pool and builds the next block.
//!
//! The block builder listens for canonical state changes from the engine and updates the
//! transaction pool. These updates move transactions to the correct sub-pools. Only transactions in
//! the pending pool are considered for the next block.
```

### Public item doc comments (`///`)

Every `pub` type, trait, function, and method should have a `///` comment. Focus on the "why" not the "what" -- the type signature already tells you "what".

```rust
/// Executes a committed subdag from consensus, producing one EVM block per batch.
///
/// Each batch in the subdag becomes a separate block to support parallel basefees
/// once multiple workers are live. Empty subdags (no batches) still produce a
/// single block to accumulate leader rewards.
pub fn execute_consensus_output(/* ... */) -> Result</* ... */> {
```

### Module-level doc comments (`//!`)

One to three lines at the top of each module file, after the SPDX header if present.

```rust
// SPDX-License-Identifier: MIT or Apache-2.0
//! Payload construction from consensus output.
//!
//! Converts committed batches into EVM block payloads with correct header fields.
```

### Architecture diagrams (text-based)

Use simple ASCII/text diagrams for data flow. Keep them narrow (< 80 chars) for terminal readability.

```
Consensus Output ──> Engine ──> EVM Blocks ──> Canonical Chain
                        │
                        └──> Pool Updates ──> Batch Builder
```

## Exemplar Structure

The tel_precompile README.md is the gold standard. Adapt this structure to each crate:

### 1. Title and Overview
- `# Crate Name -- One-line Description`
- 1-2 paragraphs explaining what the crate does, its role in the system, and any important design decisions
- Mention the core abstractions upfront

### 2. Module Map
- Table with `| File | Purpose |` columns
- One row per source file or significant module
- Purpose should be a concise phrase, not a sentence

### 3. Data Flow / Lifecycle
- Show how data moves through the crate
- Use text diagrams, pseudocode, or step-by-step descriptions
- For stateful crates: show state transitions
- For processing crates: show the pipeline

### 4. Key Components (if applicable)
- Describe the main types/traits and their responsibilities
- Explain configuration options and feature flags
- Document important constants or thresholds

### 5. Security Considerations
- Threat models relevant to the crate
- Trust assumptions
- Critical invariants that must hold
- Known limitations

### 6. Testing
- How to run the crate's tests
- Test infrastructure and utilities
- Feature flags needed for testing
- Integration test locations

### Sections to include when relevant (not in every crate)
- **Storage Layout** -- for crates with persistent state
- **Gas Costs** -- for EVM-related crates
- **Access Control** -- for crates with permissioned operations
- **Dependencies and Interfaces** -- for crates with significant cross-crate integration

## Conventions

### Doc comment style
- Use `//!` for crate and module-level docs
- Use `///` for item-level docs
- First line is always a complete sentence ending with a period
- Wrap at 100 characters (the repo convention)
- Use backticks for code references: `TypeName`, `function_name()`, `module::path`
- Every source file starts with `// SPDX-License-Identifier: MIT or Apache-2.0` -- place `//!` docs after this line

### Cross-references
- Use intra-doc links: `[`TypeName`]`, `[`module::TypeName`]`
- For cross-crate references: `[`tn_types::ConsensusOutput`]`
- For external crates: `[`reth_provider::BlockReader`]`
- Test that links resolve by running `cargo doc`

### Examples in doc comments
- Include `# Examples` for public functions with non-obvious usage
- Examples must compile (they run as doc tests)
- Use `# fn main() -> eyre::Result<()> {` wrapper for examples needing error handling
- Use `# // hidden setup lines` for boilerplate

### README conventions
- Use `#` for crate title, `##` for sections, `###` for subsections
- Tables use GitHub-flavored markdown
- Code blocks specify the language: ` ```rust `, ` ```bash `, ` ```text `
- No trailing whitespace
- Single newline at end of file

## Rules

1. **Read before writing.** Always complete Phase 1 and Phase 2 before generating any documentation. You cannot write accurate docs without understanding the code.

2. **Accuracy over completeness.** Never invent behavior. If you are uncertain about what a function does, read the implementation. If you are still uncertain, document what you can verify and leave a `TODO:` comment for the rest.

3. **Follow the exemplar.** The tel_precompile README.md is the quality bar. Match its depth, specificity, and structure. Generic hand-wavy descriptions are not acceptable.

4. **Preserve existing docs.** Do not delete or rewrite existing doc comments unless they are factually wrong. Extend them. If a `lib.rs` already has `//!` comments, add to them rather than replacing.

5. **No empty sections.** If a section from the exemplar structure does not apply to the target crate, omit it entirely. Do not write "N/A" or placeholder text.

6. **Test your examples.** Any code in doc comments must compile. Run `cargo test -p <crate> --doc` before declaring the task complete.

7. **Use subagents for large crates.** If a crate has more than 10 source files, dispatch subagents to read and summarize modules in parallel. Synthesize their findings before writing.

8. **Security sections are mandatory.** Every crate that handles consensus, networking, keys, or state must have a Security Considerations section. For pure utility crates, this section may be omitted.

9. **Verify with cargo doc.** Always run `cargo doc -p <crate-name> --no-deps` after adding docs and report the warning count before and after.

10. **Match the repo voice.** The existing documentation is direct and technical -- no marketing language, no hedging ("might", "could potentially"), no filler. State facts plainly.

11. **One commit per crate.** When documenting a crate, all documentation changes for that crate go in a single commit. Do not mix documentation for multiple crates in one commit.

12. **Do not create files that already exist without reading them first.** If a README.md already exists for the crate, read it, then extend or improve it rather than overwriting.
