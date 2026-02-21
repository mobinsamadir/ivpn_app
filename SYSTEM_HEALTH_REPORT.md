# System Health & Vulnerability Report

**Date:** October 26, 2023
**Auditor:** Jules (AI Assistant)
**Version:** 1.1 (Post-Audit Update)
**Target:** Android & Flutter Ecosystem

## 1. Memory Leaks & Resource Management

### ✅ [RESOLVED] Stream Subscription Leaks in UI
- **Location:** `lib/screens/connection_home_screen.dart`
- **Issue:** The `_funnelService.progressStream` and `_nativeVpnService.connectionStatusStream` were listened to without cancellation.
- **Resolution:** Subscriptions are now assigned to variables and properly cancelled in the `dispose()` method.
- **Status:** **FIXED**

### ✅ [RESOLVED] HttpClient Leak in EphemeralTester (Android)
- **Location:** `lib/services/testers/ephemeral_tester.dart` (Android Path)
- **Issue:** The `HttpClient` created for Stage 2/3 testing was not guaranteed to close on exceptions.
- **Resolution:** `client.close()` has been moved to a `finally` block to ensure resource cleanup regardless of test outcome.
- **Status:** **FIXED**

---

## 2. Android OS Compliance & Background Execution

### ✅ [RESOLVED] Missing Notification Permission (Android 13+)
- **Location:** `AndroidManifest.xml`
- **Issue:** The app lacked `android.permission.POST_NOTIFICATIONS`.
- **Resolution:** The permission has been added to `AndroidManifest.xml`.
- **Status:** **FIXED**

### 🟠 WARNING: Battery Optimization (Doze Mode)
- **Location:** General App Configuration
- **Issue:** The app does not request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- **Impact:** On aggressive Android skins (Samsung OneUI, Xiaomi MIUI), the OS may kill the Flutter Activity to save battery. While the `SingboxVpnService` (Native) *should* survive as a foreground service, the lack of an explicit exemption increases the risk of the VPN tunnel being killed after ~30 minutes of screen-off time.
- **Proposed Solution:** Add a "Battery Optimization" check in the Settings screen to guide users to disable optimizations for this app.

---

## 3. Error Handling & Config Parsing

### 🔵 INFO: Robustness in Config Generation
- **Location:** `lib/services/singbox_config_generator.dart`
- **Issue:** The generator assumes valid inputs in several places (e.g., `Uri.parse`). While wrapped in `try-catch` blocks at the top level, specific failures (like invalid Base64 in VMess) throw generic exceptions.
- **Impact:** Functional but could be cleaner. The current `compute` isolation prevents app crashes, so this is low severity.
- **Proposed Solution:** Introduce custom `ConfigParsingException` types to provide more actionable error messages to the user (e.g., "Invalid VMess URL" instead of "Exception: ...").

### ✅ [RESOLVED] EphemeralTester Android Crash
- **Location:** `lib/services/testers/ephemeral_tester.dart`
- **Issue:** The `runTest` method called `BinaryManager.ensureBinary()` unconditionally, which is unsupported on Android.
- **Resolution:** Logic refactored to use `NativeVpnService.startTestProxy` on Android, strictly bypassing `BinaryManager`.
- **Status:** **FIXED**

---

## 4. State Management Performance

### 🔵 INFO: UI Throttling
- **Location:** `lib/services/config_manager.dart`
- **Status:** **Good.** The `notifyListenersThrottled` implementation effectively prevents UI jank during rapid config updates (e.g., during a Funnel test).
- **Recommendation:** Maintain this pattern.

---

## 5. Security Data Storage

### 🔴 CRITICAL: Plain Text Storage of Credentials
- **Location:** `lib/services/config_manager.dart` -> `SharedPreferences`
- **Issue:** Full VPN configurations (`VpnConfigWithMetrics`), including private keys, UUIDs, and passwords (in `rawConfig`), are serialized to JSON and stored as plain text in `SharedPreferences`.
- **Impact:**
  - **Rooted Devices:** Any app with root access can read `input_vpn_configs` and steal premium server credentials.
  - **Backup Exploits:** Android Auto-Backup (if enabled) might upload these unencrypted keys to Google Drive.
- **Proposed Solution:**
  - **Immediate:** Disable Android Auto-Backup for the shared prefs file.
  - **Long-term:** Use `flutter_secure_storage` to encrypt the sensitive `rawConfig` field, or encrypt the JSON string before saving to `SharedPreferences` using a device-specific key.

---

## Summary of Remaining Action Items

1.  **Secure Storage:** Plan migration to encrypted storage for sensitive VPN credentials.
2.  **Battery Optimization:** Implement user guidance or permission request for `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
3.  **Config Robustness:** Improve error messaging for malformed configs (Low Priority).
