# tn-bug-scan Bug Pattern Catalog

Reference for all tn-bug-scan phase agents. Patterns are grouped by category and framed as *failure modes*, not attack modes. Each pattern lists: the smell, the code signature, the failure mode, and a repro sketch.

Patterns distilled from `tn-harden` (panic/determinism/blocking), `state-inconsistency-auditor` (coupled-state), and `feynman-auditor` (ordering/assumption) — plus telcoin-network-specific patterns observed in prior audits.

## How to Use

- Phase 0 (recon) uses these as hit-list seeds.
- Phase 2 (Feynman) uses each pattern as a question template.
- Phase 3 (state check) uses coupled-state patterns to build the mutation matrix.
- Phase 5 (scenario) uses the repro sketches as failure-scenario templates.
- Phase 6 (verifier) checks whether a reported finding matches a *known false-positive shape* from the pattern catalog.

## 1. Concurrency Patterns

### 1.1 Lock-across-await

- **Smell:** a synchronous lock (`parking_lot::Mutex`, `std::sync::Mutex`, `RwLock`) acquired before an `.await`.
- **Code signature:**
  ```rust
  let guard = state.lock();  // parking_lot
  do_async_work().await;     // lock held across await
  ```
- **Failure mode:** `crash` (deadlock) or `liveness-degradation` (runtime thread stall).
- **Repro:** any two tasks that both hit this path under load; the second task spins waiting for a lock the first released but whose task never resumed.
- **Telcoin-network hotspots:** `parking_lot` is widely used; watch any async handler in `crates/consensus/`, `crates/network-libp2p/`, `crates/state-sync/`.

### 1.2 Task cancellation drops state

- **Smell:** an async function mutates state, then `.await`s — if the caller drops the future, the mutation is left uncompleted.
- **Code signature:**
  ```rust
  state.insert(key, pending_value);
  self.channel.send(msg).await?;  // caller drops here
  state.mark_complete(key);       // never runs
  ```
- **Failure mode:** `state-corruption` / `silent-wrong-state`.
- **Repro:** parent task hits its own timeout and drops the child; state remains in `pending` forever.
- **TN hotspot:** `tokio::select!` branches, certificate fetcher, state-sync handlers.

### 1.3 Unbounded channel / queue

- **Smell:** `tokio::sync::mpsc::unbounded_channel`, `crossbeam::unbounded`, `VecDeque::push` with no `.len()` cap.
- **Code signature:**
  ```rust
  let (tx, rx) = unbounded_channel();
  ```
- **Failure mode:** `liveness-degradation` → eventually `crash` (OOM).
- **Repro:** peer floods the node faster than the handler drains.
- **TN hotspot:** peer-facing handlers, metric emission loops.

### 1.4 Send/recv race on shutdown

- **Smell:** receive loop exits on channel close; sender continues to push.
- **Code signature:** `send().unwrap()` on a channel whose receiver can drop.
- **Failure mode:** `crash` on the panic during shutdown or reconfiguration.
- **Repro:** reconfigure epoch, old channel drops, producer panics.

### 1.5 HashMap concurrent mutation via interior shared-state

- **Smell:** `Arc<Mutex<HashMap<..>>>` where two tasks `.insert()` and `.remove()` with no ordering invariant.
- **Failure mode:** `silent-wrong-state` if the same key is inserted+removed in the same tick.
- **Repro:** parallel handlers hit the same key; the later `.remove()` wins.

## 2. Determinism Patterns

### 2.1 HashMap iteration into consensus output

- **Smell:** `HashMap` / `HashSet` from `std::collections` iterated via `.iter()` / `.keys()` / `.values()` and the result flows into a certificate, commit order, leader choice, or reputation score.
- **Code signature:**
  ```rust
  let digests: Vec<_> = self.certs.iter().map(|(k, v)| v.digest()).collect();
  certificate.append_digests(&digests);  // certificate content now validator-dependent
  ```
- **Failure mode:** `chain-fork` — validators build different certificates from the same logical state.
- **Repro:** two validators process the same set of digests; each iterates their HashMap in a different order; certificates diverge; quorum never forms on a single chain.
- **SAFE exception:** `FxHashMap`/`FxHashSet` in `crates/storage/src/archive/` use deterministic `FxHasher` — do NOT flag.

### 2.2 SystemTime / Instant influencing consensus

- **Smell:** `SystemTime::now()` or `Instant::now()` is read and its value feeds a value that must match across validators (e.g., a certificate timestamp field, a leader election input).
- **Code signature:**
  ```rust
  let header = Header {
      timestamp: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
      ..
  };
  ```
- **Failure mode:** `chain-fork` if the timestamp is part of the digest; `consensus-stall` if the wall-clock skew exceeds the validity window.
- **Repro:** two validators produce headers in the same round with different wall-clock readings; the receiver rejects one.

### 2.3 Non-seeded RNG

- **Smell:** `thread_rng()`, `rand::random()`, `OsRng::default()` used to pick a value that must match across validators (a shuffle, a committee pick, a nonce).
- **Failure mode:** `chain-fork` or `fund-flow-divergence`.
- **Repro:** the committee shuffle computes different orderings on each validator.

### 2.4 Inner HashMap in DAG structure

- **Smell:** `BTreeMap<Round, HashMap<AuthorityIdentifier, Certificate>>` iterated to produce an ordered result. Outer is sorted; inner is not.
- **Code signature:**
  ```rust
  for (_round, inner) in &self.dag {
      for (_auth, cert) in inner {  // inner non-deterministic
          out.push(cert.digest());
      }
  }
  ```
- **Failure mode:** `chain-fork` on any downstream consumer that assumes `out` is canonical.

### 2.5 Floating-point in consensus math

- **Smell:** `f32`/`f64` used in quorum calculation, fee math, or vote weighting.
- **Failure mode:** `chain-fork` — different platforms produce different rounding.

### 2.6 par_iter producing ordered output

- **Smell:** `rayon::par_iter()` whose result is collected and treated as ordered.
- **Failure mode:** `chain-fork` if the parallel scheduler reorders chunks.

## 3. Consensus Patterns

### 3.1 Stake-weighted quorum math off-by-one

- **Smell:** `votes >= (total * 2 / 3) + 1` vs `votes > (total * 2 / 3)` vs `votes * 3 >= total * 2 + 1`. Each is subtly different.
- **Failure mode:** `consensus-stall` (too strict) or `chain-fork` (too loose — two conflicting commits).
- **Repro:** committee size where `2 * total / 3` is not integer; one check rounds down, another rounds up.

### 3.2 Signature verification skipped on a fast path

- **Smell:** a cached-validation path that skips signature verification because the certificate was once verified.
- **Failure mode:** `chain-fork` if the cache is poisoned or the key rotated.
- **Repro:** a peer replays a stale certificate; the fast path accepts it without re-verifying against the current epoch's keys.

### 3.3 Round / epoch boundary mishandling

- **Smell:** a message arrives with round N but the local state has already advanced to N+1, or vice-versa. The handler accepts, rejects, or silently proceeds.
- **Failure mode:** `consensus-stall` (legitimate message dropped) or `state-corruption` (stale message applied to wrong state).
- **Repro:** network partition heals during round N+1; peer delivers a round-N batch; local state applies it to round N+1's slot.

### 3.4 Equivocation not rejected

- **Smell:** two messages from the same authority in the same round / epoch arrive; the handler stores both instead of rejecting the second.
- **Failure mode:** `chain-fork` — downstream consumer sees two "valid" headers and picks inconsistently.

### 3.5 Vote aggregator accepts out-of-committee votes

- **Smell:** aggregator keys on authority ID but does not cross-check that the authority is in the *current* committee.
- **Failure mode:** `consensus-stall` (quorum never forms because non-committee votes count toward the bucket) or `chain-fork`.

### 3.6 Certificate validation gap at epoch transition

- **Smell:** certificate validation uses the *previous* epoch's committee to validate a certificate whose round belongs to the new epoch (or vice-versa).
- **Failure mode:** `consensus-stall` or `chain-fork`.
- **Repro:** certificate arrives during the exact tick when the epoch boundary is crossed.

## 4. State-Atomicity Patterns

### 4.1 Partial mutation on failure

- **Smell:** a function mutates two pieces of state; the second mutation can fail; the first mutation is not rolled back.
- **Code signature:**
  ```rust
  self.balance.insert(acc, new_balance);   // A
  self.checkpoint.update(acc, now)?;       // B — can fail; A stays
  ```
- **Failure mode:** `state-corruption` / `silent-wrong-state`.
- **Repro:** B fails on the first call; A persists; next read sees A with stale B.

### 4.2 Coupled-state gap

- **Smell:** two pieces of state must agree (cache ↔ canonical store; in-memory ↔ on-disk; accumulator ↔ sum-of-components). One mutation path updates only one side.
- **Failure mode:** `silent-wrong-state` / `fund-flow-divergence`.
- **TN hotspots:** gas accumulator ↔ epoch boundary catchup; DAG cache ↔ consensus DB; EVM state ↔ system-contract bindings.

### 4.3 Mid-flush crash

- **Smell:** batched writes are buffered; crash between buffer and durable flush loses writes that the caller believes committed.
- **Failure mode:** `state-corruption` on restart.
- **Repro:** node panic after `insert()` but before `flush()` / `sync()`.

### 4.4 Missing transactional boundary

- **Smell:** two DB writes that must be atomic are made in separate transactions or separate table scopes.
- **Failure mode:** `state-corruption` on crash between the two.
- **TN hotspot:** any cross-table write in the REDB layer; any `reth_db` MDBX write paired with a consensus-DB write.

### 4.5 Asymmetric delete

- **Smell:** `delete(A[key])` without `delete(B[key])` where A and B are coupled.
- **Failure mode:** `silent-wrong-state` — B grows unbounded with orphan entries.

### 4.6 Lazy reconciliation that never triggers

- **Smell:** a coupled state is "reconciled on next read" but no caller reads it until something goes wrong.
- **Failure mode:** `state-corruption` — state drifts until a downstream consumer trips.

## 5. Panic-Surface Patterns

### 5.1 .unwrap() / .expect() on untrusted input

- **Smell:** `.unwrap()` on a value derived from a peer message, RPC input, database read, or channel send.
- **Code signature:**
  ```rust
  let msg: Header = bincode::deserialize(&bytes).unwrap();  // peer bytes
  ```
- **Failure mode:** `crash`.
- **Repro:** peer sends malformed bytes.

### 5.2 Slice indexing without bounds check

- **Smell:** `slice[i]` where `i` is untrusted or derived from untrusted input.
- **Failure mode:** `crash`.

### 5.3 Integer overflow in release

- **Smell:** `a + b`, `a * b`, `a - b` where overflow is possible and the code is not in debug mode.
- **Code signature:** any arithmetic on `u64` block numbers, slot indices, balance accumulators.
- **Failure mode:** `silent-wrong-state` in release (wraps); `crash` in debug.
- **Fix:** `checked_add` / `saturating_sub` / explicit overflow handling.

### 5.4 debug_assert! as a production guard

- **Smell:** a `debug_assert!(condition)` followed by code that depends on `condition` being true.
- **Failure mode:** release-build `crash` further downstream, OR `silent-wrong-state` if downstream handles the violation gracefully.
- **Rule:** `debug_assert!` is *not* a guard. Read as if the line does not exist in release.

### 5.5 todo!() / unimplemented!() / unreachable!() on reached path

- **Smell:** any of these macros in non-test code that is actually reachable.
- **Failure mode:** `crash`.

### 5.6 Panic in `Drop`

- **Smell:** `Drop::drop` that can panic (unwrap, arithmetic, index).
- **Failure mode:** `crash` (double-panic = abort) or `liveness-degradation` (drop order corruption).

### 5.7 Unwrap after HashMap insert

- **Smell:** `map.insert(k, v); map.get(&k).unwrap()` — usually safe but not if concurrent modification is possible.
- **Failure mode:** `crash` under concurrency.

## 6. Fork-Risk Patterns

### 6.1 Block-height-dependent logic without gating

- **Smell:** `if block.number >= N { new_behavior } else { old_behavior }` without an explicit fork flag / chain-spec check.
- **Failure mode:** `chain-fork` if the constant differs across binaries.

### 6.2 Upgrade-unsafe state migration

- **Smell:** a schema change that assumes all validators upgrade simultaneously; no migration script; no version field in the persisted state.
- **Failure mode:** `chain-fork` during rolling upgrade.

### 6.3 Validator-private cache influencing output

- **Smell:** a cache whose population history differs across validators (warm after replay vs cold on fresh sync) produces different outputs.
- **Failure mode:** `chain-fork` when the cached path and the non-cached path diverge.

### 6.4 Gas schedule / chain-spec read at wrong time

- **Smell:** block-construction code reads a chain-spec value at construction time; verification reads the same value at verification time; the value can change in between.
- **Failure mode:** `chain-fork`.

### 6.5 System-call ordering divergence

- **Smell:** EVM block construction's system-call sequence is not fixed across all code paths (slashes-then-incentives vs incentives-then-slashes).
- **Failure mode:** `chain-fork` — state roots diverge.
- **TN hotspot:** `crates/tn-reth/src/system_calls.rs`.

## 7. Error-Propagation Patterns

### 7.1 Context-losing `.map_err(|_| ...)`

- **Smell:** `.map_err(|_| DefaultError)` throws away the source error; upstream can't diagnose.
- **Failure mode:** `liveness-degradation` via undiagnosable production failure (not a bug *per se*, but a bug multiplier).

### 7.2 `.ok()` swallows errors silently

- **Smell:** `fallible_call().ok();` — return value ignored, error dropped.
- **Failure mode:** `silent-wrong-state` if the call was a required side effect.

### 7.3 Catch-all match arm

- **Smell:** `_ => { /* ignore */ }` in a match over an enum; the enum gains a new variant later and the new variant is silently ignored.
- **Failure mode:** `silent-wrong-state` on enum extension.

### 7.4 Async cancel path drops error

- **Smell:** `tokio::select!` branch cancels the other; the cancelled branch's error never surfaces.
- **Failure mode:** `silent-wrong-state`.

### 7.5 Error converted to `Option::None`

- **Smell:** `.ok()` or `match result { Ok(v) => Some(v), Err(_) => None }` used in a path where the caller can't distinguish "absent" from "failed".
- **Failure mode:** `silent-wrong-state`.

## 8. Pattern Cross-Reference

| Category | Primary file hotspots |
|----------|----------------------|
| concurrency | `crates/network-libp2p/`, `crates/state-sync/`, async handlers in `crates/consensus/` |
| determinism | `crates/consensus/primary/src/aggregators/`, DAG traversal, committee / reputation |
| consensus | `crates/consensus/primary/`, `crates/consensus/executor/`, certificate validation |
| state-atomicity | `crates/storage/`, `crates/tn-reth/`, epoch transition code, gas accumulator |
| panic-surface | message deserialization, DB reads, channel sends, all async handlers |
| fork-risk | `crates/tn-reth/src/system_calls.rs`, EVM payload builder, chain-spec readers |
| error-propagation | cross-crate boundaries, async cancellation paths |

## 9. Known False-Positive Shapes

Findings matching these shapes should be examined extra-carefully in Phase 6:

- `HashMap` used only for `.get()` / `.contains()` / `.insert()` — no iteration → not a determinism bug.
- `.unwrap()` on the line immediately following an `.is_some()` check in a single-threaded function → usually safe.
- `parking_lot` lock held only for a synchronous block with no `.await` inside → usually safe.
- `SystemTime` used only for logging, metrics, or record TTL → not a consensus bug.
- `debug_assert!` immediately followed by code that short-circuits on the negation (`if !cond { return; }`) → the `if` IS the guard; debug_assert is redundant, not dangerous.
- `FxHashMap`/`FxHashSet` in `crates/storage/src/archive/` → deterministic hasher, not a fork risk.
- `HashMap` hidden behind a trait that returns `Vec<_>` sorted by the callee → check the callee's sort before flagging.
