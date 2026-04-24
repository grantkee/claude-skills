---
name: tn-domain-consensus
description: |
  Domain expert reference for the BFT consensus layer of telcoin-network — Bullshark
  ordering, certificate construction and validation, vote aggregation, header chains,
  DAG invariants, and quorum math.
  Loaded by tn-rust-engineer and tn-domain-reviewer agents when work touches the primary,
  certifier, proposer, executor (consensus output), or aggregator code paths.
  Teaches the rules that keep validators in agreement on what was committed.
  NOT user-invocable. Loaded programmatically by tn-* agents via the Skill tool.
---

# tn-domain-consensus

Consensus is the layer where Byzantine fault tolerance is actually enforced. Up to `f` of `3f+1` validators may be malicious. Every rule in this layer exists to ensure that no two honest validators ever commit conflicting state, even when up to `f` peers are actively trying to make that happen.

If you are about to modify code that:

- lives under `crates/consensus/primary/**`, `crates/consensus/worker/**`, `crates/consensus/executor/**`
- handles certificates, headers, votes, parents, or any DAG construction
- aggregates votes, validates quorum, or makes leader-election decisions
- emits, consumes, or transforms `ConsensusOutput`
- crosses the consensus/execution boundary (executor crate)

…load this skill before writing a single line.

## Why consensus is different

Honest validators are not enough — the protocol must work despite up to `f` validators acting arbitrarily. Every check, every aggregation, every state transition must assume the input might be adversarial. The two consequences:

1. **Validation is non-negotiable.** Every certificate, header, and vote that crosses an interface must have its signatures verified against the *active committee for that message's epoch*, with quorum thresholds enforced exactly. Off-by-one in quorum math is a safety violation, not a bug.
2. **Equivocation must be detectable.** A validator producing two conflicting headers in the same round breaks safety. The DAG construction and certifier must reject (and ideally surface) equivocation rather than silently absorbing it.

## Invariants

1. **Quorum is `2f+1` of the active committee for the message's epoch, not the receiving node's epoch.** A header for epoch N requires `2f+1` votes from epoch N's committee. The local node may already be in epoch N+1; quorum still references the message's epoch. Mixing committees across epochs corrupts the validation.

2. **Certificate validation must verify all parent references exist and are themselves validated.** A certificate at round R points at certificates from round R-1. Accepting a certificate without validating its parents breaks DAG integrity — equivocation in a parent silently propagates.

3. **Headers within an epoch use strictly sequential rounds.** Round R+1 cannot be voted on until round R has a `2f+1` quorum of certificates. Skipping rounds, accepting late round R after round R+2 has formed quorum, or building parents from non-adjacent rounds violates DAG construction.

4. **Equivocation rejection is mandatory.** Two distinct headers from the same author in the same round is a safety violation. The certifier must reject the second header and refuse to vote for it. Storing both is acceptable for evidence; signing both is not.

5. **`ConsensusOutput` must be idempotent and ordered.** The executor must process outputs in `consensus_number` order with no gaps and no repeats. Reordering or skipping an output causes execution divergence.

## Pre-write Checklist

1. **What committee am I validating against?** Name the epoch. If the answer is "the local node's current epoch", check whether the message's epoch matches — if not, the validation is wrong.

2. **What's the quorum threshold?** `2f+1` where `f = floor((n-1)/3)`. Compute `n` from the *message's epoch's* committee, not the local committee. Off-by-one is a safety bug.

3. **Are parents validated before the child?** If you're processing a certificate or header, walk its parent references and confirm each parent passed validation. Don't trust a child whose parents you haven't checked.

4. **What's the equivocation story?** If the operation involves an author signing something, what stops them from signing two conflicting things? Is the existing certifier check still in the code path you're touching?

5. **Does this preserve `ConsensusOutput` ordering?** If you're emitting or transforming `ConsensusOutput`, what guarantees consecutive numbering and no skips?

6. **Is any input from a peer (not yet validated)?** If yes, treat it as adversarial. Validate before deriving anything from it.

## Canonical Sources

| Value | Source | Why this and not other sources |
|---|---|---|
| Active committee for epoch N | `EpochRecord` for epoch N in `ConsensusChain` | Live `ConsensusRegistry` may have rolled to N+1 |
| Quorum threshold for epoch N | `2 * f + 1` where `f = (committee.size() - 1) / 3` | Hardcoded numbers, "majority", or `committee.len() / 2 + 1` are all wrong |
| Last committed leader for round R | `ConsensusChain::leader_at(R)` after consensus has resolved R | Local computation before commit; speculative leaders |
| Parent certificates of cert C | `C.parents()` — must be validated independently | Trusting that C.parents() exist because C signed them |
| Vote signature scheme | BLS12-381 via `blst`, with epoch-tagged signing payload | Any non-epoch-tagged payload (allows replay across epochs) |
| Round monotonicity | Local round counter advanced only after `2f+1` certs at current round | Time-based round advancement; speculative advance |

## Common Bug Patterns

### Pattern 1: Wrong-committee quorum check

```rust
// WRONG — uses local committee, but the cert is for a different epoch
let quorum = 2 * (self.committee.size() - 1) / 3 + 1;
if cert.signers().count() >= quorum { ... }
```

The fix: derive the committee and quorum from `cert.epoch()`, not from `self`. If the local node doesn't have that epoch's committee in storage, that's an error to surface — not a reason to fall back to the current epoch.

### Pattern 2: Trusting unvalidated parents

```rust
// WRONG — accepts cert without validating parents exist and are correct
fn process_cert(&mut self, cert: Certificate) -> Result<()> {
    self.store(cert)?;
    Ok(())
}
```

The fix: walk `cert.parents()`, look each up in storage, and confirm validation status. Reject the cert if any parent is missing or unvalidated.

### Pattern 3: Hardcoded quorum threshold

```rust
// WRONG — assumes a fixed committee size
const QUORUM: usize = 5;
if votes.len() >= QUORUM { ... }
```

Committee sizes change at epoch boundaries (validators join, exit, get slashed). Always derive quorum from the current committee size.

### Pattern 4: Silent equivocation tolerance

```rust
// WRONG — overwrites the prior header instead of detecting equivocation
self.headers.insert((author, round), new_header);
```

The fix: check whether `(author, round)` already has a different header. If yes, that's equivocation — reject the new one (and surface it for slashing if applicable).

## Further Reading

- `references/invariants.md`
- `references/bug-patterns.md`
- `references/canonical-sources.md`
