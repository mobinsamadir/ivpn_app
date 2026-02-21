# System Health & Vulnerability Report

**Date:** October 26, 2023
**Auditor:** Jules (AI Assistant)
**Version:** 1.0
**Target:** Android & Flutter Ecosystem

## 1. Memory Leaks & Resource Management

### 🔴 CRITICAL: Stream Subscription Leaks in UI
- **Location:** `lib/screens/connection_home_screen.dart`
- **Issue:** The `_funnelService.progressStream` and `_nativeVpnService.connectionStatusStream` are listened to in `initState()` without assigning the subscription to a variable.
- **Impact:** If the user navigates away from `ConnectionHomeScreen` (e.g., to Settings) and back, or if the widget is disposed, the subscriptions remain active. This causes:
  1.  **Memory Leaks:** The widget cannot be garbage collected.
  2.  **"SetState() called after dispose()" Errors:** The stream listener will try to update the UI of a defunct widget.
- **Proposed Solution:**
  -  Assign subscriptions to `StreamSubscription` variables (e.g., `_progressSubscription`, `_statusSubscription`).
  -  Cancel them in `dispose()`.

### 🟠 WARNING: HttpClient Leak in EphemeralTester (Android)
- **Location:** `lib/services/testers/ephemeral_tester.dart` (Android Path)
- **Issue:** The `HttpClient` created for Stage 2/3 testing is closed (`client.close()`) *outside* the `try-catch` block. If an exception occurs during the HTTP request (Stage 2), the execution jumps to the `catch` block, skipping the close call.
- **Impact:** `HttpClient` resources (sockets) are leaked on every failed test, eventually leading to `SocketException: Too many open files` or network exhaustion.
- **Proposed Solution:** Move `client.close()` to a `finally` block or ensure it is called in the `catch` path.

---

## 2. Android OS Compliance & Background Execution

### 🔴 CRITICAL: Missing Notification Permission (Android 13+)
- **Location:** `AndroidManifest.xml` & `MainActivity.kt`
- **Issue:** Android 13 (API 33+) requires the runtime permission `android.permission.POST_NOTIFICATIONS` for Foreground Services to show notifications.
  - The manifest does not declare this permission.
  - The runtime code does not request it.
- **Impact:** The VPN "Connected" notification will be silently blocked by the OS. The Foreground Service might still run, but the user loses visibility and control (cannot stop VPN from notification shade).
- **Proposed Solution:**
  - Add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` to `AndroidManifest.xml`.
  - In `MainActivity` or `AppInitializer`, check and request this permission on startup.

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

### 🔴 CRITICAL: EphemeralTester Android Crash
- **Location:** `lib/services/testers/ephemeral_tester.dart`
- **Issue:** The `runTest` method calls `BinaryManager.ensureBinary()` unconditionally. On Android, this throws an `UnsupportedError` because the binary is not bundled (it uses JNI).
- **Impact:** Pre-flight checks fail immediately on Android, preventing connection if `_connectWithFailover` relies on it.
- **Proposed Solution:** Refactor `runTest` to use `NativeVpnService.startTestProxy` or `NativeVpnService.measurePing` on Android, avoiding `BinaryManager` entirely.

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

## Summary of Action Items

1.  **Fix EphemeralTester on Android:** Prevent calls to `BinaryManager`.
2.  **Fix Stream Leaks:** Properly cancel subscriptions in `ConnectionHomeScreen`.
3.  **Fix HttpClient Leak:** Use `finally` block in `EphemeralTester`.
4.  **Add Permissions:** Add `POST_NOTIFICATIONS` to Manifest.
5.  **Secure Storage:** Plan migration to encrypted storage.
