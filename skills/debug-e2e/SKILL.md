---
name: debug-e2e
description: |
  Debug failing end-to-end tests in the telcoin-network blockchain protocol repo.
  Use this skill whenever the user shares e2e test output (stdout/stderr), mentions a failing e2e test,
  asks about test_logs, or wants help diagnosing issues in crates/e2e-tests/.
  Trigger on: test failures, panics, timeouts, assertion errors, race conditions,
  epoch boundary issues, node restart failures, consensus hangs, or any e2e test debugging.
  Also trigger when the user pastes log output containing telcoin-network node traces,
  consensus errors, or execution engine failures from test runs.
---

# Debug E2E Tests - Telcoin Network

You are debugging end-to-end test failures in the telcoin-network repo, a DAG-based blockchain protocol (Narwhal/Bullshark consensus + EVM execution on Reth). The primary concern is **race condition bugs**, though test harness issues occasionally surface.

## Overview

E2e tests live in `crates/e2e-tests/`. They spawn 4-6 validator processes and test consensus, epoch transitions, node restarts, and state sync. Logs are saved to `crates/e2e-tests/test_logs/<test_name>/` with per-node stdout and stderr files.

Race conditions in this codebase typically stem from:
- **Timing gaps** between synchronous consensus state updates and async engine processing
- **Shutdown ordering** where data is saved to DB but not forwarded on channels
- **Channel subscription windows** where messages are lost during epoch transitions
- **Concurrent access** to shared state without proper per-entity locking
- **Broadcast channel lag** causing slow receivers to silently drop messages

These are often symptoms of architectural complexity. Solutions should simplify, not add more coordination.

## Step 1: Parse the Failure

From the user's stdout/stderr, extract:
1. **Test name** (e.g., `epoch_boundary`, `restarts`, `reconnect`, `epoch_sync`, `late_join`, `observer`, `restarts_delayed`, `restarts_lagged_delayed`)
2. **Failure type**: panic, assertion failure, timeout, hang, unexpected state
3. **Error messages**: the specific error text, panic location, or assertion details
4. **Timing clues**: how far into the test it failed (which epoch, which round, which node)

If the user hasn't provided enough context, ask for the full test output or point them to the log directory.

## Step 2: Parallel Investigation

Launch subagents to investigate in parallel. Keep each subagent focused on one concern to minimize context window usage.

### Subagent 1: Log Analysis
```
Analyze the e2e test logs for the failing test.

Read the log files in crates/e2e-tests/test_logs/<test_name>/.
Focus on:
- ERROR and WARN level messages across all nodes
- Timing of events: when did each node start, reach consensus, execute blocks
- The last meaningful events before the failure
- Any signs of: channel lag, missed messages, hung waits, timeout expiry
- Differences in event ordering between nodes (a node that's behind or ahead)

Log format: [TIMESTAMP] [LEVEL] [TARGET]: message [field=value ...]
Node logs: node<N>-run<N>.log (stdout) and .stderr.log

Report: timeline of significant events per node, anomalies, and the specific point of failure.
```

### Subagent 2: Test Code Analysis
```
Read the failing test code and the test harness.

Read:
- The specific test file in crates/e2e-tests/tests/it/ that matches the failing test
- crates/e2e-tests/src/lib.rs (test harness: node spawning, RPC setup, log configuration)
- crates/e2e-tests/tests/it/common.rs (ProcessGuard, TestSemaphore, cleanup)

Focus on:
- What the test is asserting and the sequence of operations
- Timeout values and polling intervals
- How nodes are spawned, killed, and restarted (if applicable)
- Any assumptions about ordering or timing that could be violated
- Where the test waits for conditions and what could cause those waits to fail

Report: test flow, critical timing assumptions, and potential fragility points.
```

### Subagent 3: Relevant Source Code
```
Based on the error from the failing test, search the source code for the root cause.

Key areas to investigate based on the failure type:

For consensus/round issues:
- crates/consensus/primary/src/consensus_bus.rs (channel architecture, wait functions)
- crates/consensus/primary/src/network/handler.rs (vote handling, "behind" detection)

For epoch boundary issues:
- crates/node/src/manager/node/epoch.rs (epoch transitions, shutdown coordination)
- crates/consensus/executor/src/subscriber.rs (biased select, shutdown drain)

For execution/block issues:
- crates/engine/src/lib.rs (ExecutorEngine, block building)
- crates/consensus/executor/src/subscriber.rs (consensus output forwarding)

For networking issues:
- crates/network-libp2p/ (peer discovery, connection management)

For state sync issues:
- crates/state-sync/ (sync protocol)

Search for the specific error message in the codebase. Trace the code path that produces it.
Look for:
- tokio::select! without biased (potential for missed priorities)
- watch/broadcast channel send patterns (send vs send_replace)
- Lock ordering and potential deadlocks
- Missing timeout guards on wait operations
- Assumptions about channel delivery ordering

Report: the code path that leads to the failure, any concurrency hazards found.
```

## Step 3: Synthesize and Diagnose

After subagent results return, synthesize the findings:

1. **Correlate the timeline**: Match log events across nodes with the test sequence and source code flow
2. **Identify the race window**: Pinpoint the exact timing gap or ordering violation
3. **Trace the causal chain**: From the architectural decision that created the race window, through the trigger condition, to the observable failure
4. **Check against known patterns**: Compare with previously fixed race conditions in this repo (see reference file)

## Step 4: Explain and Solve

Present findings in this structure:

### Root Cause
- What happened and why, explained from the architecture down to the specific code
- The race window: what two (or more) concurrent operations are competing
- Why the current design allows this race

### Evidence
- Specific log entries, timestamps, and code locations that demonstrate the issue
- How the failure differs from the successful case

### Solution
Solutions should follow these principles for this codebase:

1. **Simplify over coordinate** - If the fix requires adding another mutex, channel, or synchronization point, consider whether the architecture can be simplified instead. Complex coordination is the source of most race conditions here.

2. **Use biased select for shutdown paths** - `tokio::select! { biased; }` ensures data processing completes before shutdown signals are handled. This pattern has resolved multiple issues in this codebase.

3. **Separate "saved" from "forwarded" tracking** - Don't assume that writing to DB means the downstream consumer received the data. Track forwarding progress explicitly.

4. **Per-entity locking over global locking** - When concurrent operations on different entities are safe, use per-entity locks (e.g., `HashMap<Id, TokioMutex<_>>`) to maximize parallelism.

5. **Watch channels for state, broadcast for events** - Use `watch` with `send_replace()` for latest-value state. Use `broadcast` for event streams, but handle `Lagged` errors explicitly.

6. **Include committed state in "behind" calculations** - When checking if a component is behind, consider all state sources (execution round, processed consensus round, committed round).

7. **Add timeout guards on waits** - Even "should never block" operations need timeouts as safety nets.

8. **Phase 2 recovery scans** - For critical data paths, add startup/recovery scans that compare DB state against forwarding state to catch anything that was persisted but not delivered.

Provide:
- The specific code changes needed (with file paths and line numbers)
- Why this solution addresses the root cause rather than masking symptoms
- Any broader architectural improvements that would prevent similar issues

## Key Architecture Context

Read `references/architecture.md` for the full crate map and data flow if you need deeper context on how the system fits together.

Read `references/race-conditions.md` for documented patterns of previously fixed race conditions — check whether the current issue matches a known pattern before proposing novel solutions.
