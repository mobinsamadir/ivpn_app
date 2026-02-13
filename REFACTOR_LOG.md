# Refactor Log: VPN Application Modernization

This log tracks all architectural changes, refactors, and migrations performed to modernize the VPN application.

## Phase 1: Core Utilities (Robustness)
- [x] Implement `Base64Utils` with safe decoding logic.
- [x] Refactor `ConfigImporter` to use `Base64Utils`.
- [x] Refactor `SingboxConfigGenerator` to use `Base64Utils`.
- [x] Refactor `ConfigManager` to implement robust Google Drive download logic (HTML parsing, confirm token handling).

## Phase 2: Data Model & Migration (Safety)
- [x] Update `VpnConfigWithMetrics` with `funnelStage`, `speedScore`, `failureCount`.
- [x] Ensure safe `fromJson` parsing for legacy data compatibility.
- [x] Implement new `compareTo` sorting logic (Stage > Score > Latency).

## Phase 3: The Ephemeral Engine (Resource Safety)
- [x] Create `EphemeralTester` service.
- [x] Implement secure ephemeral port binding (`ServerSocket.bind`).
- [x] Implement strict process management with hard timeouts and cleanup (`finally` block).
- [x] configure Sing-box JSON template (Fatal logging, Localhost binding).

## Phase 4: The Funnel Service (The Brain)
- [x] Create `FunnelService` with priority queue logic.
- [x] Implement Stage 1: TCP Handshake (1.5s).
- [x] Implement Stage 2: Ghost Buster (HTTPS 204 Check).
- [x] Implement Stage 3: Speed Test (Cloudflare 1MB).
- [x] Implement Concurrency Control (Semaphore).

## Phase 5: Cleanup & UI
- [x] Delete legacy `ServerTesterService.dart`.
- [x] Delete legacy `LatencyService.dart`.
- [x] Update `ConnectionHomeScreen` to use `FunnelService` streams.
- [x] Add progress indicators and control buttons to UI.

---
**Log Entries:**
- **Phase 1 Complete:** Created `Base64Utils` to handle safe decoding with padding completion. Replaced all unsafe `base64Decode` calls in `ConfigImporter`, `SingboxConfigGenerator`, and `ConfigManager`.
- **ConfigManager Refactor:** Implemented robust Google Drive logic. It now checks for "Virus scan warning" and extracts the `confirm` token via Regex or HTML parsing strategies, then retries the download. Added strict content validation to ensure fetched content starts with valid protocol headers or is valid Base64.
- **Phase 2 Complete:** Updated `VpnConfigWithMetrics` model. Added `funnelStage` (0-3) and `speedScore` (0-100) fields. Updated `fromJson` to handle missing fields with default values (0), ensuring existing user data won't cause crashes. Implemented `Comparable` interface with the new sorting logic: `funnelStage` (DESC) -> `speedScore` (DESC) -> `latency` (ASC).
- **Phase 3 Complete:** Created `EphemeralTester` service. It uses `ServerSocket.bind` for ephemeral ports and wraps Sing-box execution in a `Process.start` with a hard 5s timeout. JSON config is generated with `fatal` logging and localhost bindings for isolation. Strict cleanup logic (`finally` block) ensures processes are killed and temp files deleted. Implemented multi-stage logic (TCP -> HTTP 204 -> Speed) within the tester.
- **Phase 4 Complete:** Created `FunnelService` to manage testing queues. Implemented priority logic (Tier 1 Retest > Tier 2 Fresh > Tier 3 Retry). Added concurrency control (Max 5 concurrent tests) using a custom waiter queue. Integrated with `EphemeralTester` to run the multi-stage validation pipeline.
- **Phase 5 Complete:** Removed legacy `ServerTesterService` and `LatencyService`. Deleted `StabilityChartScreen` as requested. Updated `ConnectionHomeScreen` to act as the consumer for `FunnelService`, displaying real-time progress. Integrated "Stop Test" functionality and replaced old "Funnel" logic with the new `FunnelService.startFunnel()`.
