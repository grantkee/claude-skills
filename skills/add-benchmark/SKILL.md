---
name: add-benchmark
description: |
  Generate Criterion benchmarks for telcoin-network hot paths.
  Trigger on: "benchmark", "add bench", "performance test", "criterion", "measure latency", "throughput test"
---

# Criterion Benchmark Generator

## Project Context

telcoin-network is a Rust blockchain node combining Narwhal/Bullshark DAG-based BFT consensus with EVM execution via Reth. The workspace lives at the repo root with crates under `crates/`.

Key facts for benchmarking:

- **No existing benchmarks**: There are no `benches/` directories, no `[[bench]]` sections, and no `criterion` dependency in the workspace yet. Everything must be scaffolded from scratch.
- **Serialization**: BCS (`bcs` crate) for general encoding, `bincode` (with `fixint_encoding` + big endian) for DB keys, `snap` for compression. See `crates/types/src/codec.rs`.
- **Hashing**: `blake3` is the default hash function (`DefaultHashFunction = blake3::Hasher`). Batch digests use blake3 over BCS-encoded bytes.
- **Crypto**: BLS signatures via `blst` crate (min_sig variant, BLS12-381 G1). Signing, verification, and aggregation are in `crates/types/src/crypto/`.
- **Parallelism**: `rayon` is used in `BatchValidator::decode_transactions` for parallel transaction recovery (`par_iter`).
- **Test fixtures**: `TransactionFactory` in `crates/tn-reth/src/test_utils.rs`, `CommitteeFixture` / `AuthorityFixture` in `crates/test-utils-committee/`, `TestPool` in `crates/batch-builder/src/test_utils.rs`.
- **Workspace dep style**: All dependencies go in `[workspace.dependencies]` in root `Cargo.toml`, then crates reference them with `{ workspace = true }`.
- **Lints**: The workspace enforces `unused_crate_dependencies = "warn"`, so benchmark crates need `#[allow(unused_crate_dependencies)]` or explicit feature-gating.

## Process

### Phase 1: Identify the target hot path

Ask the user which hot path to benchmark, or select from the reference below. Confirm:
- Which crate owns the code
- Whether the benchmark needs async runtime (tokio) or is purely sync
- What the input dimensions are (number of transactions, number of signatures, byte sizes)
- Whether test-utils features are needed

### Phase 2: Set up Criterion scaffolding

For each crate that gets a benchmark:

1. **Add `criterion` to workspace dependencies** in the root `Cargo.toml` under `[workspace.dependencies]`:

```toml
criterion = { version = "0.5", features = ["html_reports"] }
```

2. **Add to the target crate's `Cargo.toml`**:

```toml
[dev-dependencies]
criterion = { workspace = true }

[[bench]]
name = "bench_name"
harness = false
```

3. **Create `crates/<crate>/benches/bench_name.rs`**.

4. **Add `make bench` target** to the root `Makefile` (append after existing targets):

```makefile
# run criterion benchmarks
bench:
	cargo bench --workspace ;

# run criterion benchmarks for a specific crate
bench-crate:
	@if [ -z "$(CRATE)" ]; then \
		echo "Error: CRATE is required. Usage: make bench-crate CRATE=tn-batch-validator"; \
		exit 1; \
	fi
	cargo bench --package $(CRATE) ;
```

Also update the `.PHONY` line and `help` target to include `bench` and `bench-crate`.

### Phase 3: Write the benchmark following conventions

- Use `criterion_group!` and `criterion_main!` macros.
- Use `Criterion::measurement_time` to set warm-up and measurement durations.
- Use `BenchmarkId::new` with a descriptive label for parameterized runs.
- Use `Throughput::Bytes` or `Throughput::Elements` for throughput metrics.
- Use `iter_batched` (with `BatchSize::SmallInput` or `LargeInput`) to separate setup from measured code.
- Keep benchmark names descriptive: `"batch_validation/100_txs"`, `"bls_verify/single"`, etc.
- Add `#![allow(missing_docs, unused_crate_dependencies)]` at the top of each bench file.

### Phase 4: Verify it runs and collect baseline

```bash
cargo bench --package <crate-name> -- --warm-up-time 1 --measurement-time 3
```

Check that:
- It compiles without warnings
- Criterion produces a report in `target/criterion/`
- The numbers are plausible (not measuring setup time)

Save baseline for future comparison:
```bash
cargo bench --package <crate-name> -- --save-baseline main
```

## Hot Path Reference

### 1. Batch Building (worker)

- **Crate**: `tn-batch-builder`
- **Function**: `build_batch<P: TxPool>(args, worker_id, base_fee) -> BatchBuilderOutput`
- **Location**: `crates/batch-builder/src/batch.rs`
- **What it does**: Pulls best transactions from the pending pool, enforces gas limit (`max_batch_gas` = 30M) and byte size limit (`max_batch_size` = 1MB), builds a `Batch` struct.
- **Benchmark approach**: Create a `TestPool` with N pre-signed transactions, measure `build_batch` throughput varying N (10, 100, 500, 1000). Use `Throughput::Elements(n)`.
- **Setup**: Use `TransactionFactory::new()` to create encoded EIP-1559 transactions, feed into `TestPool::new()`.
- **Async**: No -- purely synchronous.
- **Test utils needed**: `tn-batch-builder` with `test-utils` feature, `tn-reth` with `test-utils` feature.

### 2. Batch Validation (with rayon parallelism)

- **Crate**: `tn-batch-validator`
- **Function**: `BatchValidator::validate_batch(sealed_batch) -> Result<(), BatchValidationError>`
- **Location**: `crates/batch-validator/src/validator.rs`
- **What it does**: Verifies digest, decodes + recovers transactions in parallel via `rayon::par_iter`, checks gas limits, byte size, base fee, no blob txs.
- **Benchmark approach**: Create valid `SealedBatch` with N transactions, measure `validate_batch`. Separately benchmark `decode_transactions` (the rayon-parallel portion). Use `Throughput::Elements(n)`.
- **Setup**: Requires `RethEnv::new_for_temp_chain`, `TransactionFactory`, temp directory, `TaskManager`. See test file for `test_tools()` pattern.
- **Async**: `validate_batch` is sync, but setup needs tokio for `RethEnv`.
- **Test utils needed**: `tn-reth` with `test-utils`, `tempfile`, `tokio`.

### 3. Block Execution / Payload Building

- **Crate**: `tn-engine`
- **Function**: `execute_consensus_output(args, gas_accumulator, engine_update_tx) -> EngineResult<SealedHeader>`
- **Location**: `crates/engine/src/payload_builder.rs`
- **What it does**: Takes consensus output (batches from DAG), builds + executes EVM blocks, extends the canonical chain.
- **Benchmark approach**: Complex setup -- requires full Reth environment. Better suited for integration-level benchmarks. Measure per-block execution time.
- **Async**: Uses tokio channels but core execution is sync.

### 4. BLS Signature Operations

- **Crate**: `tn-types`
- **Key types**: `BlsKeypair`, `BlsSignature`, `BlsAggregateSignature`, `BlsPublicKey`
- **Location**: `crates/types/src/crypto/bls_*.rs`
- **Operations to benchmark**:
  - `BlsKeypair::sign(msg)` -- single signature creation
  - `BlsSignature::verify_raw(msg, pubkey)` -- single verification
  - `BlsSignature::new_secure(intent_msg, keypair)` -- protocol-aware signing (BCS encode + sign)
  - `BlsSignature::verify_secure(intent_msg, pubkey)` -- protocol-aware verification
  - `BlsAggregateSignature::aggregate(&[sigs], true)` -- aggregate N signatures
  - `BlsAggregateSignature::verify_secure(msg, &[pks])` -- aggregate verification with N public keys
- **Benchmark approach**: Parameterize aggregate operations by N (1, 4, 10, 50, 100). Single ops get simple latency benchmarks.
- **Setup**: `BlsKeypair::generate(&mut StdRng::from_os_rng())`, fixed test messages.
- **Async**: No -- purely synchronous.
- **Dependencies**: `blst`, `rand`, `bcs` (all already in workspace).

### 5. Serialization (BCS, bincode, snap)

- **Crate**: `tn-types`
- **Functions**: `encode()` / `decode()` (BCS), `encode_key()` / `decode_key()` (bincode), snap compress/decompress
- **Location**: `crates/types/src/codec.rs`
- **Benchmark approach**: Serialize/deserialize `Batch`, `SealedBatch`, `Header`, `Certificate` at various sizes. Measure bytes/sec throughput.
- **Setup**: Construct types using test helpers or fixtures.
- **Async**: No.

### 6. Committee / Quorum Calculations

- **Crate**: `tn-types`
- **Functions**: `Committee::quorum_threshold()`, `Committee::reached_quorum()`, `quorum_threshold(n)`
- **Location**: `crates/types/src/committee.rs`
- **Benchmark approach**: These are fast arithmetic operations -- only worth benchmarking if called in hot loops. Lower priority.

### 7. Batch Sealing (blake3 hashing)

- **Crate**: `tn-types`
- **Function**: `Batch::seal_slow() -> SealedBatch`
- **Location**: `crates/types/src/worker/sealed_batch.rs`
- **What it does**: BCS-encodes the batch, then blake3-hashes it to produce the digest.
- **Benchmark approach**: Create batches with varying transaction counts, measure seal time. This combines serialization + hashing. Use `Throughput::Bytes(batch_size)`.
- **Async**: No.

## Benchmark Patterns

### Throughput Benchmark (transactions/sec)

```rust
#![allow(missing_docs, unused_crate_dependencies)]

use criterion::{
    criterion_group, criterion_main, BenchmarkId, Criterion, Throughput, BatchSize,
};

fn bench_operation(c: &mut Criterion) {
    let mut group = c.benchmark_group("operation_name");

    for n in [10, 100, 500, 1000] {
        group.throughput(Throughput::Elements(n as u64));
        group.bench_with_input(BenchmarkId::new("label", n), &n, |b, &n| {
            b.iter_batched(
                || {
                    // setup: create input of size n
                    create_input(n)
                },
                |input| {
                    // measured code
                    operation(input)
                },
                BatchSize::SmallInput,
            );
        });
    }

    group.finish();
}

criterion_group!(benches, bench_operation);
criterion_main!(benches);
```

### Latency Benchmark (single operation)

```rust
fn bench_single_op(c: &mut Criterion) {
    // setup outside the benchmark loop
    let keypair = BlsKeypair::generate(&mut StdRng::from_os_rng());
    let message = b"benchmark message";

    c.bench_function("bls_sign", |b| {
        b.iter(|| keypair.sign(criterion::black_box(message)))
    });
}
```

### Parameterized Benchmark (varying N)

```rust
fn bench_aggregate_verify(c: &mut Criterion) {
    let mut group = c.benchmark_group("bls_aggregate_verify");

    for n in [1, 4, 10, 50, 100] {
        let keypairs: Vec<BlsKeypair> = (0..n)
            .map(|_| BlsKeypair::generate(&mut StdRng::from_os_rng()))
            .collect();
        let msg = to_intent_message(b"bench payload".to_vec());
        let sigs: Vec<BlsSignature> = keypairs
            .iter()
            .map(|kp| BlsSignature::new_secure(&msg, kp))
            .collect();
        let pks: Vec<BlsPublicKey> = keypairs.iter().map(|kp| *kp.public()).collect();
        let agg = BlsAggregateSignature::aggregate(&sigs, true).unwrap();

        group.throughput(Throughput::Elements(n as u64));
        group.bench_with_input(
            BenchmarkId::new("verify", n),
            &(&agg, &msg, &pks),
            |b, (agg, msg, pks)| {
                b.iter(|| agg.verify_secure(msg, pks));
            },
        );
    }

    group.finish();
}
```

### Setup with Reth Environment (for batch validator)

```rust
use std::sync::Arc;
use tempfile::TempDir;
use tn_reth::{test_utils::TransactionFactory, RethChainSpec, RethEnv};
use tn_types::{
    test_genesis, Address, Batch, Bytes, TaskManager, MIN_PROTOCOL_BASE_FEE, U256,
};

fn setup_batch_validator() -> (BatchValidator, TempDir, TaskManager) {
    let tmp_dir = TempDir::new().unwrap();
    let task_manager = TaskManager::default();
    let chain: Arc<RethChainSpec> = Arc::new(test_genesis().into());

    // RethEnv::new_for_temp_chain is sync-safe for setup
    let reth_env = RethEnv::new_for_temp_chain(
        chain.clone(),
        tmp_dir.path(),
        &task_manager,
        None,
    ).unwrap();

    let validator = BatchValidator::new(
        reth_env,
        None,  // no tx pool needed for validation benchmarks
        0,     // worker_id
        BaseFeeContainer::default(),
        0,     // epoch
    );

    (validator, tmp_dir, task_manager)
}

fn create_valid_sealed_batch(n: usize, chain: Arc<RethChainSpec>) -> SealedBatch {
    let mut tx_factory = TransactionFactory::new();
    let value = U256::from(10).checked_pow(U256::from(18)).unwrap();
    let transactions: Vec<Vec<u8>> = (0..n)
        .map(|_| {
            tx_factory.create_eip1559_encoded(
                chain.clone(),
                None,
                7,
                Some(Address::ZERO),
                value,
                Bytes::new(),
            )
        })
        .collect();

    let batch = Batch {
        transactions,
        epoch: 0,
        beneficiary: Address::ZERO,
        base_fee_per_gas: MIN_PROTOCOL_BASE_FEE,
        worker_id: 0,
        received_at: None,
    };

    batch.seal_slow()
}
```

## Cargo.toml Setup

### Root Cargo.toml (workspace dependency)

Add under `[workspace.dependencies]`:

```toml
criterion = { version = "0.5", features = ["html_reports"] }
```

### Crate Cargo.toml

```toml
[dev-dependencies]
criterion = { workspace = true }
# Add other test dependencies as needed:
# tempfile = { workspace = true }
# tn-reth = { workspace = true, features = ["test-utils"] }

[[bench]]
name = "bench_name_here"
harness = false
```

The `harness = false` is mandatory -- it tells Cargo to use Criterion's own main function instead of the built-in test harness.

If the crate has multiple benchmark files, add a separate `[[bench]]` section for each:

```toml
[[bench]]
name = "batch_building"
harness = false

[[bench]]
name = "batch_validation"
harness = false
```

## Conventions

- **File location**: `crates/<crate>/benches/<bench_name>.rs`
- **Naming**: Snake case matching the operation: `batch_building.rs`, `bls_operations.rs`, `serialization.rs`
- **Group naming**: Use `/` separators for Criterion groups: `"batch_build/from_pool"`, `"bls/sign"`, `"bls/verify_aggregate"`
- **Parameterization**: Use powers or practical sizes: `[1, 10, 100, 1000]` for transactions, `[1, 4, 10, 50, 100]` for validators/signatures
- **Throughput units**: `Throughput::Elements` for discrete items (txs, sigs), `Throughput::Bytes` for data processing
- **Black box**: Always wrap return values with `criterion::black_box()` to prevent dead code elimination
- **Measurement time**: Default 5s is fine for most benchmarks. Use `group.measurement_time(Duration::from_secs(10))` for noisy benchmarks
- **Sample size**: Default 100 is fine. Reduce with `group.sample_size(50)` for expensive benchmarks (e.g., full block execution)
- **File header**: Always include `#![allow(missing_docs, unused_crate_dependencies)]` to satisfy workspace lints

## Rules

1. **Never benchmark setup code**: Use `iter_batched` or `iter_with_setup` to separate allocation/construction from the measured operation.
2. **Always add `harness = false`**: Without this, Cargo tries to use the default test harness and the benchmark will not compile.
3. **Workspace dependency first**: Add `criterion` to root `Cargo.toml` `[workspace.dependencies]`, then reference with `{ workspace = true }` in the crate.
4. **One group per concern**: Do not mix unrelated operations in the same benchmark group. Separate files for separate hot paths.
5. **Parameterize thoughtfully**: Choose input sizes that reflect real-world usage. Telcoin batches typically contain 10-1000 transactions. Committees are typically 4-100 validators.
6. **Keep benchmarks deterministic**: Use seeded RNGs (`StdRng::from_seed([0; 32])`) for reproducible results. Avoid `from_os_rng()` inside the measured loop.
7. **Verify correctness first**: Before benchmarking, make sure the operation produces correct results with a debug assertion in setup or a separate test.
8. **Do not benchmark in CI by default**: Criterion benchmarks are noisy in CI. Add `make bench` as an opt-in target, not part of `make pr` or `make test`.
9. **Respect the lint rules**: The workspace uses strict lints. Add `#![allow(missing_docs, unused_crate_dependencies)]` at the top of each benchmark file.
10. **Save baselines**: When establishing a benchmark for the first time, run with `-- --save-baseline main` so future runs can compare with `-- --baseline main`.
11. **Temp directories for Reth**: Any benchmark involving `RethEnv` needs a `TempDir`. Create it in setup, keep it alive for the duration of the benchmark group. The `TempDir` drops and cleans up automatically.
12. **Avoid tokio runtime in measured code**: If setup requires async (e.g., `RethEnv`), build a runtime in setup and `block_on` there. The measured code should be synchronous whenever possible.
