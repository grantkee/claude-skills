# Consensus-domain invariants — full reference

## I-1: Quorum references the message's epoch's committee

**Rule.** Quorum thresholds (`2f+1`) and signature verification use the committee active for the *message's* epoch, not the receiving node's current epoch. Cross-epoch validation must explicitly look up the historical committee.

**Where it must hold.** Certificate validation, vote aggregation, header validation in `crates/consensus/primary/src/aggregators/**` and certifier paths.

**Check.** For every quorum computation, trace `f` back to its source. If `f` is computed from `self.committee` or `self.epoch`, but the message has its own `epoch()` accessor, this is wrong unless those epochs are explicitly equal.

## I-2: Parent certificates are validated independently

**Rule.** Accepting a certificate at round R requires that all of `cert.parents()` (round R-1 references) exist in storage and have themselves passed validation. Trust does not transit through a signature.

**Where it must hold.** Certifier ingest, header validation, DAG insertion, batch fetch validation.

**Check.** Look at every code path that stores or accepts a certificate. If parents are not looked up and validated, the cert can carry references to equivocations or invented parents.

## I-3: Round monotonicity and density

**Rule.** Round R+1 only opens after `2f+1` certificates are stored for round R. Headers built with parents from non-adjacent rounds (R, R-3) are protocol violations. Late-arriving round R certificates must be processed but must not roll the round counter back.

**Where it must hold.** Proposer round logic, certifier round tracking, DAG round-density checks.

**Check.** For round-advance code, confirm the counter only moves forward, only after quorum, and only based on the local DAG view, not peer signals alone.

## I-4: Equivocation rejection

**Rule.** Two distinct headers from the same author in the same round must not both be signed by an honest validator. The first observed must be voted for; the second must be rejected (and ideally retained as evidence).

**Where it must hold.** Certifier vote logic, header-store inserts.

**Check.** Anywhere a header is stored or voted on, look for a check that a header from the same `(author, round)` doesn't already exist. If the existing header differs, that's equivocation.

## I-5: `ConsensusOutput` ordering

**Rule.** The stream of `ConsensusOutput` to the executor is strictly ordered by `consensus_number` with no skips and no repeats. Re-emission on restart must replay from the right cursor.

**Where it must hold.** `crates/consensus/executor/**`, the `to_engine` mpsc, `replay_missed_consensus`.

**Check.** When changing emission or recovery code, confirm that the cursor advances by exactly one per output and that recovery starts at `engine.last_executed_consensus_number() + 1`.
