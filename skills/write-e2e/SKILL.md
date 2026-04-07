---
name: write-e2e
description: |
  Design and generate end-to-end tests for the telcoin-network node.
  Trigger on: "write e2e test", "integration test", "test epoch", "test restart", "test sync", "end to end"
---

# E2E Test Generator

## Project Context

Telcoin Network (tn-4) is a Rust blockchain node combining Narwhal/Bullshark DAG-based BFT consensus with EVM execution via Reth. The e2e test suite lives in `crates/e2e-tests/` and exercises the full node binary -- genesis ceremony, multi-validator networks, epoch transitions, restarts, staking, and observer nodes.

Architecture:
- **4-5 validator nodes** run as child processes per test, each with its own temp directory, dynamic RPC/WS/IPC ports, and per-node log files
- **`spawn_local_testnet()`** handles the simple case: config + launch all 4 validators in-process via `launch_node()`
- **`get_telcoin_network_binary()` + `start_nodes()`** handles the process-based case: compile the `telcoin-network` binary once (cached via `OnceLock<CargoRun>`), then spawn child processes with full CLI args
- **ProcessGuard** ensures all child processes are killed on drop (SIGTERM then SIGKILL), preventing orphaned nodes even on panic
- **TestSemaphore** limits concurrent e2e tests to 2 (each spawns 4-6 processes)
- Tests use `#[ignore]` so they don't run in `cargo test` by default -- run with `cargo test --ignored` or `--include-ignored`

Key files:
- `crates/e2e-tests/src/lib.rs` -- harness: `spawn_local_testnet()`, `config_local_testnet()`, `setup_log_dir()`, `get_telcoin_network_binary()`, `verify_all_transports()`, `NodeEndpoints`
- `crates/e2e-tests/tests/it/common.rs` -- `ProcessGuard`, `TestSemaphore`, `acquire_test_permit()`, `kill_child()`, `send_term()`
- `crates/e2e-tests/tests/it/main.rs` -- test module declarations
- `crates/e2e-tests/tests/it/epochs.rs` -- epoch boundary + epoch sync tests
- `crates/e2e-tests/tests/it/restarts.rs` -- restart, delayed restart, observer tests
- `crates/e2e-tests/tests/it/genesis_tests.rs` -- genesis verification, precompile accounts, ConsensusRegistry
- `crates/e2e-tests/tests/it/staking.rs` -- CLI keygen to stake flow (uses RethEnv directly, not spawned nodes)
- `crates/e2e-tests/Cargo.toml` -- dependencies

## Process

### Phase 1: Understand the Test Scenario

Ask or determine:
1. What behavior is being tested? (epoch transition, restart recovery, genesis state, staking, observer sync, custom)
2. Does this test need spawned node processes or can it use `RethEnv` directly?
3. How many validators? Any additional nodes (observer, new validator joining)?
4. What transactions need to be submitted? (staking, transfers, contract calls)
5. What are the success criteria? (block height advances, validator in committee, balances match, epoch records certified)

### Phase 2: Design the Test

Before writing code, plan:

1. **Setup**: What genesis configuration is needed? Custom accounts? Custom epoch duration?
2. **Network topology**: How many validators, any observers, any late-joining nodes?
3. **Actions**: What sequence of operations? (wait for RPC, submit txs, kill node, restart node, wait for epoch)
4. **Assertions**: What to verify at each step? Be specific about block heights, balances, committee membership, epoch records.
5. **Timing**: Account for EPOCH_DURATION, RPC startup delay (up to 20s), epoch boundary confirmation lag, and CI load variance. Always use generous timeouts.
6. **Cleanup**: ProcessGuard handles this, but verify the guard scope covers all code paths.

### Phase 3: Generate the Test Code

Write the test following harness conventions (see sections below). The test must:
- Acquire `TestSemaphore` permit as the first action
- Use `tempfile::TempDir` for all data
- Wrap all child processes in `ProcessGuard`
- Use dynamic ports via `get_available_tcp_port()`
- Poll RPC until ready (never assume instant availability)
- Use `timeout()` around all blocking waits
- Return `eyre::Result<()>`

### Phase 4: Verify and Provide Run Instructions

1. Verify the test compiles: `cargo check -p e2e-tests --tests`
2. If a new module is created, add it to `crates/e2e-tests/tests/it/main.rs`
3. Provide the run command: `cargo test -p e2e-tests --test it <test_name> -- --ignored --nocapture`
4. Note where logs will be written: `crates/e2e-tests/test_logs/<test_name>/`

## Test Harness Reference

### spawn_local_testnet()

The simplest way to start a 4-validator network. Runs nodes **in-process** using threads (not child processes). Returns `Vec<NodeEndpoints>`.

```rust
let temp_dir = tempfile::TempDir::with_prefix("my_test")?;
let endpoints = spawn_local_testnet(temp_dir.path(), None)?;
// endpoints[0].http_url, endpoints[0].ws_url, endpoints[0].ipc_path
```

With funded accounts:
```rust
let accounts = vec![
    (address, GenesisAccount::default().with_balance(U256::from(parse_ether("50_000_000")?))),
];
let endpoints = spawn_local_testnet(temp_dir.path(), Some(accounts))?;
```

Limitation: no per-node process control (can't kill/restart individual nodes). Use the process-based approach for restart tests.

### Process-Based Approach (for restart/kill scenarios)

Used by `epochs.rs` and `restarts.rs`. Compile the binary once, spawn as child processes:

```rust
let bin = e2e_tests::get_telcoin_network_binary();
let mut guard = ProcessGuard::empty();

for (i, (name, _addr)) in validators.iter().enumerate() {
    let rpc_port = get_available_tcp_port("127.0.0.1").expect("rpc port");
    let ws_port = get_available_tcp_port("127.0.0.1").expect("ws port");
    let ipc_path = temp_path.join(format!("{name}.ipc"));

    let mut command = bin.command();
    command
        .env("TN_BLS_PASSPHRASE", NODE_PASSWORD)
        .arg("--bls-passphrase-source").arg("env")
        .arg("node")
        .arg("--datadir").arg(&*dir.to_string_lossy())
        .arg("--http").arg("--http.port").arg(rpc_port.to_string())
        .arg("--ws").arg("--ws.port").arg(ws_port.to_string())
        .arg("--ipcpath").arg(ipc_path.to_string_lossy().as_ref());

    setup_log_dir(&mut command, name, "my_test", 1);
    guard.push(command.spawn().expect("failed to execute"));
}
// guard.take(idx) -- remove for manual restart
// guard.replace(idx, new_child) -- swap in restarted node
// guard.kill_all() or drop -- cleanup
```

### ProcessGuard

RAII guard that kills all child processes on drop (SIGTERM -> poll 6s -> SIGKILL).

```rust
let _guard = ProcessGuard::new(children);          // wrap existing Vec<Child>
let mut guard = ProcessGuard::empty();              // build incrementally
let idx = guard.push(child);                        // add, returns index
let old = guard.take(idx);                          // remove for manual control
guard.replace(idx, new_child);                      // swap (restart scenario)
guard.send_term_all();                              // SIGTERM without waiting
guard.kill_all();                                   // SIGTERM + wait + SIGKILL
```

### TestSemaphore

Limits concurrent e2e tests to `MAX_CONCURRENT_TESTS` (currently 2). Must be acquired first in every test:

```rust
let _permit = super::common::acquire_test_permit();
// also initializes test tracing
```

### RPC Polling

Never assume RPC is available immediately. Poll until ready:

```rust
// Using alloy Provider
timeout(Duration::from_secs(20), async {
    let mut result = provider.get_chain_id().await;
    while let Err(e) = result {
        tokio::time::sleep(Duration::from_secs(1)).await;
        result = provider.get_chain_id().await;
    }
}).await?;

// Using jsonrpsee HttpClient (restarts.rs pattern)
fn wait_for_rpc(url: &str) -> eyre::Result<HttpClient> {
    let client = HttpClientBuilder::default().build(url)?;
    for attempt in 0..120 {
        match client.request::<String, _>("eth_blockNumber", rpc_params!()).await {
            Ok(_) => return Ok(client),
            Err(_) => tokio::time::sleep(Duration::from_millis(500)).await,
        }
    }
    eyre::bail!("RPC not available")
}
```

### Transaction Submission

Use `TransactionFactory` for signing and `ConsensusRegistry` bindings for validator operations:

```rust
// Create wallet
let mut wallet = TransactionFactory::new_random_from_seed(&mut StdRng::seed_from_u64(42));

// Build and send a transaction
let chain: Arc<RethChainSpec> = Arc::new(genesis.into());
let calldata = ConsensusRegistry::mintCall { validatorAddress: addr }.abi_encode().into();
let tx = wallet.create_eip1559_encoded(
    chain.clone(),
    None,           // gas_limit (None = default)
    100,            // gas_price
    Some(CONSENSUS_REGISTRY_ADDRESS),
    U256::ZERO,     // value
    calldata,
);

// Send via provider
let pending = provider.send_raw_transaction(&tx).await?;
timeout(Duration::from_secs(EPOCH_DURATION * 2 + 11), pending.watch()).await??;
```

### Epoch Polling

Poll `ConsensusRegistry::getCurrentEpochInfo()` to detect epoch transitions:

```rust
let consensus_registry = ConsensusRegistry::new(CONSENSUS_REGISTRY_ADDRESS, &provider);
let mut current_info = consensus_registry.getCurrentEpochInfo().call().await?;

let deadline = Instant::now() + Duration::from_secs(EPOCH_DURATION * 4);
let new_info = loop {
    let info = consensus_registry.getCurrentEpochInfo().call().await?;
    if info != current_info {
        break info;
    }
    assert!(Instant::now() < deadline, "Epoch did not change within timeout");
    tokio::time::sleep(Duration::from_secs(1)).await;
};
```

### Epoch Record Verification

Verify certified epoch records across all nodes:

```rust
for ep in endpoints {
    let provider = ProviderBuilder::new().connect_http(ep.http_url.parse()?);
    for epoch in 0..=latest_epoch {
        let deadline = Instant::now() + Duration::from_secs(EPOCH_DURATION * 3);
        let (epoch_rec, cert) = loop {
            match provider
                .raw_request::<_, (EpochRecord, EpochCertificate)>("tn_epochRecord".into(), (epoch,))
                .await
            {
                Ok(result) => break result,
                Err(_) if Instant::now() < deadline => {
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
                Err(e) => return Err(eyre::eyre!("epoch record unavailable: {e}")),
            }
        };
        assert!(epoch_rec.verify_with_cert(&cert), "invalid epoch record!");
    }
}
```

### Per-Node Logging

Every spawned node should write logs to `crates/e2e-tests/test_logs/<test>/<node>-run<N>.log`:

```rust
setup_log_dir(&mut command, "validator-1", "my_test", 1);
// Also captures stderr to node-run1.stderr.log
```

### verify_all_transports()

Verify HTTP, WS, and IPC are all reachable for a node:

```rust
verify_all_transports(&endpoints[0]).await?;
```

## Timing & Race Condition Avoidance

These patterns come from real bugs found in the codebase. Follow them strictly.

### 1. EPOCH_DURATION Awareness

Epoch-related tests use `EPOCH_DURATION` (typically 10s in tests) as the base timing unit. All timeouts should be multiples of this:
- **RPC startup**: 20s
- **Transaction confirmation**: `EPOCH_DURATION * 2 + 11` (txs can land at epoch boundaries, get orphaned, and re-inject)
- **Epoch transition polling**: `EPOCH_DURATION * 4` (generous for CI load variance)
- **Epoch record availability**: `EPOCH_DURATION * 3` (certificates are produced asynchronously after boundaries)

### 2. Deadline-Based Polling (Not Fixed Retries)

Use `Instant::now() + Duration` deadlines instead of fixed retry counts. This adapts to actual execution speed:

```rust
let deadline = Instant::now() + Duration::from_secs(EPOCH_DURATION * 4);
loop {
    // ... check condition ...
    assert!(Instant::now() < deadline, "descriptive failure message");
    tokio::time::sleep(Duration::from_secs(1)).await;
}
```

### 3. Biased Select for Shutdown

When using `tokio::select!` with both data processing and shutdown signals, always use `biased` with data arms first. Without it, shutdown can win randomly when both arms are ready, dropping the final data item.

### 4. Never Assume Instant State Propagation

After submitting a transaction or triggering an epoch change:
- Poll until the expected state is visible (don't just sleep a fixed duration)
- Use `wait_for_block(url, target_block)` before reading state from a node that might be behind
- Observer nodes lag validators -- always wait for sync before asserting

### 5. Account for Async Certificate Production

Epoch records and certificates are produced asynchronously after epoch boundaries via quorum voting. Poll with a deadline rather than assuming they exist immediately after an epoch transition.

### 6. Channel and Shutdown Ordering

Be aware of:
- **Saved-but-not-forwarded**: Data persisted to DB but channel to consumer already closed
- **Epoch transition windows**: Channels torn down and recreated between epochs, messages can be lost
- **Broadcast channel lag**: `tokio::sync::broadcast` drops messages when receiver falls behind

### 7. Restart Timing

After killing and restarting a node:
- Verify the killed node is actually down (RPC should fail)
- After restart, poll RPC until responsive (up to 45s in restart tests)
- Wait for the restarted node to sync to the current block height before asserting state equality

## Test Scenarios

### Template: Basic Genesis Verification

```rust
#[tokio::test]
async fn test_genesis_something() -> eyre::Result<()> {
    let _permit = super::common::acquire_test_permit();
    let temp_dir = tempfile::TempDir::with_prefix("genesis_something")?;
    let endpoints = spawn_local_testnet(temp_dir.path(), None)?;
    let rpc_url = &endpoints[0].http_url;

    // wait for RPC
    let client = wait_for_rpc(rpc_url).await?;

    // ... verify genesis state via RPC ...

    Ok(())
}
```

### Template: Epoch Transition with New Validator

See `epochs.rs::test_epoch_boundary()` for the full pattern:
1. Create `TransactionFactory` wallets for governance and new validator
2. `create_genesis_for_test()` with funded accounts
3. `start_nodes()` to spawn all validators + new validator
4. Wrap in `ProcessGuard`
5. Poll RPC until ready
6. Submit mint/stake/activate txs
7. Loop epochs, checking committee membership
8. Verify epoch records across all nodes

### Template: Kill and Restart Node

See `epochs.rs::test_epoch_sync()` and `restarts.rs::do_restarts()` for the full pattern:
1. Start network, wait for RPC
2. Run through N epochs
3. `guard.take(idx)` to remove a node, `kill_child()` to stop it
4. Verify the node is actually down (RPC should error)
5. Continue epochs on remaining nodes
6. `start_nodes()` to restart, `guard.replace(idx, child)` to re-register
7. Update endpoints (new dynamic ports)
8. Verify restarted node syncs and all nodes agree on state

### Template: Observer Node

See `restarts.rs::test_restarts_observer()`:
1. Start 4 validators + 1 observer with `start_observer()` (uses `--observer` CLI flag)
2. Observer data dir is `temp_path.join("observer")`
3. Send tx to observer, confirm on validator
4. `wait_for_block(obs_url, target_block)` before reading observer state
5. Send tx to validator, confirm observer sees it

### Template: Direct RethEnv Test (No Spawned Nodes)

See `staking.rs::test_cli_keygen_to_stake()`:
1. Build genesis with `RethEnv::create_consensus_registry_genesis_accounts()`
2. Create `RethEnv::new_for_temp_chain(chain, tmp_dir.path(), &task_manager, None)`
3. Build payloads with `TNPayload`, execute with `reth_env.build_block_from_batch_payload()`
4. Query state directly with `reth_env.get_validator_info()`
5. No ProcessGuard needed -- no child processes

## Conventions

### Naming
- Test functions: `test_<scenario>` (e.g., `test_epoch_boundary`, `test_restartstt`)
- Inner async helpers: `test_<scenario>_inner` for the core logic
- Helper functions: descriptive verbs (e.g., `loop_epochs`, `start_nodes`, `generate_new_validator_txs`)
- Temp dir prefixes: match the test name (e.g., `tempfile::TempDir::with_prefix("epoch_boundary")`)
- Log test names: match the test for easy log correlation

### File Placement
- New test modules go in `crates/e2e-tests/tests/it/<module>.rs`
- Register in `crates/e2e-tests/tests/it/main.rs` as `mod <module>;`
- Shared utilities go in `common.rs` (if test-specific) or `src/lib.rs` (if reusable across test binaries)

### Attributes
- All e2e tests that spawn nodes MUST have `#[ignore = "descriptive reason"]`
- Use `#[tokio::test]` for async tests, plain `#[test]` for sync tests (restart tests use sync + internal runtime)
- The `#[ignore]` attribute goes BEFORE `#[tokio::test]` or `#[test]`

### Imports
- `use super::common::{acquire_test_permit, ProcessGuard, kill_child, send_term};`
- `use e2e_tests::{...};` for harness items from `src/lib.rs`
- `use alloy::{...};` for providers, primitives
- `use tn_reth::{system_calls::{ConsensusRegistry, CONSENSUS_REGISTRY_ADDRESS}, test_utils::TransactionFactory};`
- `use tn_types::{get_available_tcp_port, Address, ...};`

### Error Handling
- Return `eyre::Result<()>` from all tests
- Use `?` for propagation, `eyre::bail!()` or `eyre::eyre!()` for custom errors
- Include context in error messages (node URL, expected vs actual values, iteration number)
- In restart tests, kill child processes before returning errors to prevent orphans

### Constants
- `EPOCH_DURATION: u64 = 10` -- base timing unit for epoch tests
- `NODE_PASSWORD: &str` -- BLS passphrase for test validators
- `INITIAL_STAKE_AMOUNT: &str = "1_000_000"` -- stake per validator
- Validator addresses: `Address::from_slice(&[0x11; 20])` through `[0x55; 20]`

## Rules

1. **Always acquire `TestSemaphore` first.** Every test function must call `acquire_test_permit()` before doing anything else. This limits concurrency and initializes tracing.

2. **Always use `ProcessGuard`.** Every spawned child process must be wrapped in a `ProcessGuard`. Never rely on manual cleanup -- panics skip manual cleanup code.

3. **Always use dynamic ports.** Call `get_available_tcp_port("127.0.0.1")` for every port. Never hardcode port numbers. Tests run in parallel.

4. **Always use `tempfile::TempDir`.** Never write to fixed paths. The TempDir handle must live for the duration of the test (don't let it drop early).

5. **Always poll RPC until ready.** Never sleep a fixed duration and hope the node is up. Poll with a timeout.

6. **Always wrap waits in `timeout()`.** Any loop that waits for a condition must have a deadline or timeout to prevent infinite hangs.

7. **Never assume instant epoch transitions.** Epoch changes, certificate production, and state propagation all happen asynchronously. Poll until observed.

8. **Use `#[ignore]` on every test that spawns nodes.** These tests are slow and resource-heavy. They must be opted into explicitly.

9. **Update `main.rs` when adding a new module.** Add `mod <name>;` to `crates/e2e-tests/tests/it/main.rs`.

10. **Write descriptive failure messages.** Include the test name, iteration number, node URL, and expected vs actual values in all assertions and error messages. When a test fails, the message should be enough to start debugging without reading the code.

11. **Separate test logic into `_inner` functions.** Keep the `#[test]` function for setup/teardown and delegate core logic to an inner function. This makes it easier to share logic across test variants (e.g., `test_epoch_boundary` and `test_epoch_sync` share epoch-polling logic).

12. **Account for epoch boundary transaction orphaning.** Transactions submitted near an epoch boundary may be orphaned and re-injected. Use `EPOCH_DURATION * 2 + buffer` for transaction confirmation timeouts.

13. **Verify node is actually down after kill.** After `kill_child()`, assert that the node's RPC is unreachable before proceeding. Do not assume the process exited instantly.

14. **Update endpoints after restart.** Restarted nodes get new dynamic ports. Always update the endpoint entry in your test state.

15. **Read `test_logs/` on failure.** When debugging, tell the user to check `crates/e2e-tests/test_logs/<test>/` for per-node stdout and stderr logs.
