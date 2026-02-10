# Tester Architecture Proposal: The "Stream Pipeline" Model
**Prepared for:** Senior Architect / Product Owner
**Date:** 2024-05-23
**Focus:** High-Throughput Server Testing with "Fail-Fast" Logic

## Executive Summary
The current `ServerTesterService` uses a **Batch-and-Wait** approach (process 50, wait for all, process next 50). This is inefficient because fast failures (ICMP dead) block the pipeline for slow successes.

This proposal refactors the system into a **Continuous Stream Pipeline** (Feed-Forward Architecture). Configs flow individually through stages. As soon as a config passes Stage 1, it immediately enters the queue for Stage 2, maximizing resource utilization.

---

## 1. The Pipeline Model (Architecture)

### Core Concept: "Feed-Forward"
Instead of `List<Config>`, we utilize Dart's `Stream` and `StreamController`.

**Visual Flow:**
`[Source Stream]` -> `[Stage 1: ICMP]` -> `[Stage 2: TCP]` -> `[Stage 3: TLS]` -> `[Stage 4: RTT]` -> `[Results Sink]`

*   **Non-Blocking:** Stage 1 doesn't wait for Stage 2.
*   **Fail-Fast:** If Config A fails at Stage 1, it is **discarded immediately** (or tagged as dead) and never touches Stage 2.
*   **Prioritization:** We can prioritize "Promising Candidates" (e.g., historical success) by pushing them into the stream first.

### Implementation Strategy
We will implement a `PipelineTester` class that manages:
1.  **Input Controller:** A `StreamController<VpnConfig>` where we push configs to be tested.
2.  **Stage Workers:** Independent async functions that consume from one stream and produce to the next.
3.  **Global Concurrency Guard:** A `Semaphore` or `TokenBucket` to limit total active sockets to **50**.

---

## 2. Concurrency Management (The "Global Pool")

**Constraint:** The OS cannot handle >50 simultaneous socket operations reliably (especially on mobile/Windows with low file descriptor limits).

**Solution:** **Global Semaphore**
*   We implement a `Semaphore` class with 50 permits.
*   **Every Stage** (ICMP, TCP, TLS, etc.) must acquire a permit before starting work.
*   **Release:** The permit is released immediately after the stage completes (pass or fail).
*   **Queueing:** If the pool is full, new tests wait in a FIFO queue until a slot opens.

**Why Global?**
*   Limiting per-stage (e.g., 50 ICMP + 50 TCP) is dangerous because it could spike to 200+ total threads. A global limit ensures system stability.

---

## 3. The Funnel Stages (Ordered by Cost)

The pipeline is ordered from **Cheapest/Fastest** to **Most Expensive**.

### Stage 1: ICMP / Ping (The "Sieve")
*   **Check:** Simple ICMP Ping or HTTP Head (to a known IP).
*   **Cost:** Very Low.
*   **Fail Action:** Mark as `Dead_ICMP`. **Drop.**
*   **Success:** Pass to Stage 2.

### Stage 2: TCP Handshake (The "Door Knocker")
*   **Check:** Attempt to open a socket to `IP:Port`.
*   **Cost:** Low.
*   **Fail Action:** Mark as `Closed_Port`. **Drop.**
*   **Success:** Pass to Stage 3.

### Stage 3: TLS / Protocol Handshake (The "Reality Check")
*   **Check:** Verify the server speaks the expected protocol (VMess/VLESS/Trojan). This filters out "Fake" or "Captcha" servers.
*   **Cost:** Medium (SSL Handshake).
*   **Fail Action:** Mark as `Protocol_Mismatch` or `Handshake_Fail`. **Drop.**
*   **Success:** Pass to Stage 4.

### Stage 4: Real Delay (RTT) (The "Benchmark")
*   **Check:** Measure precise Round-Trip Time (RTT) to the target destination (e.g., Google/Cloudflare).
*   **Cost:** Medium/High.
*   **Success:** **Save Result.** Only the top 10-20% proceed to Stage 5 (Speed Test).

### Stage 5: Speed Test (The "Heavy Lifter")
*   **Check:** Download a small file (e.g., 1MB-5MB) to measure throughput.
*   **Cost:** Very High (Bandwidth & CPU).
*   **Limit:** Only run on "Elite" candidates (Low RTT + High Stability).

---

## 4. Data Model Updates (`VpnConfigWithMetrics`)

We need to track *where* a config failed to avoid re-testing dead servers unnecessarily in the future.

**New Fields:**
```dart
class VpnConfigWithMetrics {
  // Existing fields...

  // NEW: Detailed Test Results
  final Map<String, TestResult> stageResults; // e.g., {'icmp': passed, 'tcp': failed}
  final String? lastFailedStage; // e.g., "Stage 2: TCP"
  final String? failureReason;   // e.g., "Connection Refused"
  final DateTime lastTestedAt;

  // Helper
  bool get isDead => lastFailedStage != null;
}

class TestResult {
  final bool success;
  final int latency;
  final String? error;

  TestResult({required this.success, this.latency = 0, this.error});
}
```

---

## 5. Proposed Implementation Logic (Pseudo-Code)

```dart
class PipelineTester {
  final _concurrencyLimit = Semaphore(50);
  final _outputController = StreamController<VpnConfigWithMetrics>.broadcast();

  // The Main Pipeline
  Stream<VpnConfigWithMetrics> runPipeline(List<VpnConfigWithMetrics> configs) async* {

    // 1. Create a stream from the input list
    final stream = Stream.fromIterable(configs);

    // 2. Parallel Processing with Global Limit
    // Note: We use a pool pattern here to process the stream

    await for (final config in stream) {
      // Acquire permit - waits if pool is full
      await _concurrencyLimit.acquire();

      // Run the test in a separate future (don't await here to allow concurrency)
      _processConfig(config).then((result) {
        _concurrencyLimit.release();
        if (result != null) {
          _outputController.add(result);
        }
      });
    }
  }

  Future<VpnConfigWithMetrics?> _processConfig(VpnConfigWithMetrics config) async {
    // Stage 1
    var result = await _testICMP(config);
    if (!result.passed) return result.failedConfig; // Return marked as failed

    // Stage 2
    result = await _testTCP(result.config);
    if (!result.passed) return result.failedConfig;

    // ... continue stages ...

    return result.successConfig;
  }
}
```

## 6. Migration Plan
1.  **Phase 1:** Implement the `Semaphore` and `PipelineTester` class alongside the existing `ServerTesterService`.
2.  **Phase 2:** Refactor `latency_service.dart` to expose granular methods (`checkICMP`, `checkTCP`) instead of one monolithic `getAdvancedLatency`.
3.  **Phase 3:** Swap the UI to listen to the new `pipelineStream` to show real-time updates as servers are verified.
