# Consensus-domain bug patterns

## P-1: Wrong-epoch committee in quorum

```rust
// WRONG — local committee used to validate cert from different epoch
let quorum = 2 * self.committee.size() / 3 + 1;
```

Use the committee for `cert.epoch()`, not `self.committee`. If unavailable locally, surface as error, do not fall back.

## P-2: Floor-division off-by-one

```rust
// WRONG — formula gives f = n/3 which is too generous
let f = self.committee.size() / 3;
let quorum = 2 * f + 1;
```

Right: `f = (n - 1) / 3`. For n=4, f=1, quorum=3. Off-by-one accepts insufficient signatures.

## P-3: Accepting unvalidated parents

```rust
// WRONG — stores cert without confirming parents exist & validated
self.store_cert(cert)?;
```

Walk `cert.parents()`, validate each independently. Equivocation propagates through unvalidated parent chains.

## P-4: HashMap iteration over signers

```rust
// WRONG — non-deterministic for any output that depends on ordering
for signer in cert.signers().collect::<HashMap<_, _>>().keys() { ... }
```

Use `BTreeMap` or sort. Non-determinism here can cause divergent canonical encodings.

## P-5: Replay-vulnerable signature payload

```rust
// WRONG — signs payload without epoch tag, allowing cross-epoch replay
let payload = header.digest();
sign(payload)
```

Right: include `epoch` in the signing payload. Otherwise an old vote replays into a new epoch.
