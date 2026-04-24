# Storage-domain invariants — full reference

## I-1: Co-stored rows are atomic

**Rule.** Any set of rows that depend on each other (cert+header, header+votes, epoch record + closing block, batch + index) must be written in a single atomic transaction.

**Where it must hold.** Every multi-row insert in the consensus DB; reth-side state finalization paired with epoch record writes.

**Check.** Look for sequential `put` calls without a wrapping transaction. If a crash between any two would leave the node confused, the writes need atomicity.

## I-2: One encoding per table

**Rule.** Every table has exactly one key encoding routine and one value encoding routine. All reads and writes use those routines.

**Where it must hold.** Every table accessor, every migration, every cross-module read.

**Check.** Search for direct `.put` / `.get` calls. They should route through a typed wrapper for the table. Any inline encoding in user code is a smell.

## I-3: Epoch-scoped vs persistent table lifecycles

**Rule.** Epoch-scoped tables (in-flight votes, parent candidates, leader staging) reset on `NewEpoch`. Persistent tables (certificates, headers, epoch records, blocks) never reset.

**Where it must hold.** `consensus_bus.reset_for_epoch()` and any related cleanup at epoch transition.

**Check.** Maintain a list of which tables are epoch-scoped vs persistent. New tables must declare which they are at definition time.

## I-4: Iteration order is keyed, not insertion-ordered

**Rule.** Replay and sync code that depends on order must use a key whose encoding produces the desired order. Don't rely on insertion order.

**Where it must hold.** Replay paths, sync producers, leader-counting walks.

**Check.** Any iteration that derives an order-sensitive value: confirm the key encoding sorts that way, or sort explicitly after collecting.

## I-5: Consensus DB and reth DB advance together at boundary

**Rule.** Finalizing the closing block of epoch N in reth and writing `EpochRecord` for epoch N in the consensus DB are co-dependent. A crash between them leaves the boundary ambiguous.

**Where it must hold.** Epoch-close path in epoch manager + executor.

**Check.** What's the recovery story if reth has the closing block but the consensus DB doesn't have the EpochRecord? If the answer involves re-deriving the record from reth state, that's fragile — prefer making the writes atomic via two-phase commit or a recovery cursor that both DBs share.
