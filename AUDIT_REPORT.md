# Comprehensive System Audit & Proposed Solutions Report

This report outlines the findings from a detailed audit of the Android VPN application, focusing on critical functional issues and proposed solutions.

### 1. Android Test Failure Analysis
- **The Issue:**
  - `EphemeralTester` fails on Android because it calls `BinaryManager.ensureBinary()`. This method throws an `UnsupportedError` on Android since the standalone `sing-box` binary is no longer bundled (the app uses `libbox.aar` via JNI instead).
  - This blocks the connection flow because `ConnectionHomeScreen._connectWithFailover` calls `_ephemeralTester.runTest(currentConfig)` as a "Pre-flight Check".
- **Locations Identified:**
  - `lib/services/testers/ephemeral_tester.dart`: The `runTest` method unconditionally calls `BinaryManager.ensureBinary()`.
  - `lib/screens/connection_home_screen.dart`: The `_connectWithFailover` method invokes the tester.
- **Proposed Solution:**
  - **Platform-Aware Testing:** Refactor `EphemeralTester.runTest` to detect Android.
  - **Native Integration:** On Android, delegate the test to `NativeVpnService.getPing(config.rawConfig)`. This method already performs a connectivity check (Stage 2 equivalent) using the native library.
  - **Logic:**
    - If `Platform.isAndroid`: Call `NativeVpnService.getPing`. If result > 0, return success (Stage 2 passed).
    - If `Platform.isWindows`: Continue using the existing `Process.start` logic with `BinaryManager`.

### 2. Storage Persistence & "Ghost" Configs Audit
- **The Issue:**
  - Deleted configs reappear after a "Fetch" or app restart.
  - **Root Cause:** `ConfigManager.fetchStartupConfigs` downloads the full remote list. `addConfigs` compares incoming configs against `allConfigs`. If a config is not in memory (because you deleted it), it is treated as "New" and re-added.
  - There is no "Deleted History", so the app doesn't know you explicitly removed it.
- **Proposed Solution:**
  - **Persistent Blacklist:** Implement a `deleted_configs_blacklist` in `SharedPreferences`.
  - **Workflow:**
    1. When `deleteConfig(id)` is called, calculate a hash of the config's content and add it to the blacklist.
    2. In `addConfigs(List<String>)`, filter out any incoming config whose hash matches an entry in the blacklist.
  - **Result:** Configs deleted by the user will strictly remain deleted, even if they exist in the remote source.

### 3. Implementation Plan for Reward Ads (UX/UI)
- **Requirement:** A mandatory 10-second full-screen ad before connection.
- **Current State:** The app uses `AdDialog`, which is a standard dialog (with margins), not full-screen.
- **Proposed Solution:**
  - **Full-Screen Overlay:** Change `AdDialog` to use `showGeneralDialog` with `barrierColor: Colors.black` and `pageBuilder` returning a full-screen `Scaffold`.
  - **Strict Timer Enforcement:**
    - Wrap the dialog in `PopScope` (Android 14+) or `WillPopScope` to completely disable the back button.
    - The "Close & Connect" button will remain `disabled` (or hidden) until the 10-second timer (controlled by `AdManagerService`) completes.
    - **Visuals:** Add a prominent countdown timer (e.g., "Reward in 10s...") at the top-right.

### 4. Config Priority Verification
- **The Issue:** "Ghost" configs jumping to Index 0.
- **Root Cause:** When a deleted config is re-imported (the "Ghost" issue), it is instantiated as a *new* `VpnConfigWithMetrics` object with `addedDate: DateTime.now()`.
- **Priority Logic:** `ConfigManager._updateListsSync` sorts configs added within the last 1 hour (`newConfigs`) to the top. Since re-imported ghosts have a fresh timestamp, they are prioritized as "New".
- **Proposed Solution:**
  - **Fix via Blacklist:** Solving the "Ghost Configs" issue (Item 2) is the primary fix here. If they aren't re-imported, they won't get a new timestamp.
  - **Refined Priority:** For *legitimately* new configs, ensure `addConfigs` only assigns `DateTime.now()` if the config is truly unique and not just a re-fetch of an existing (but currently missing) item.
  - **Preservation:** If needed, we can track `addedDate` in a separate metadata store, but the Blacklist solution is cleaner and solves the root cause.
