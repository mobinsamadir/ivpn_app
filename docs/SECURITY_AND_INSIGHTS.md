# Security & Vulnerability Insights

Based on a current architectural review of the `main` branch, the following are the primary areas where the app is most vulnerable or has technical debt:

## 1. Native VPN Service Event Handling
- **Issue:** The `NativeVpnService` relies on a global `EventChannel` for status updates from the native Android/Windows side.
- **Vulnerability:** If the user kills the app or the OS restricts background execution, the Flutter UI might lose sync with the actual running Sing-box instance. The current retry logic handles network drops, but OS-level process deaths of the UI while the VPN tunnel remains active are not fully reconciled on warm start.
- **Actionable Mitigation Path:**
  - Implement a two-way sync on app startup: Before initiating a new connection or assuming a disconnected state, the Flutter side should actively poll the native layer (via a `MethodChannel`) to get the real-time VPN status.
  - Implement a persistent state flag (e.g., in SharedPreferences) that the native layer updates upon successful connection/disconnection, acting as a source of truth for the UI upon warm starts.

## 2. Hardcoded / Direct File I/O in Dart
- **Issue:** Several services write configurations directly to `SharedPreferences` or disk.
- **Vulnerability:** While `compute()` is used for `SingboxConfigGenerator`, there are synchronous file checks (`existsSync`) in critical paths (like checking for the Sing-box binary on Windows). If the disk is slow or locked by an antivirus, this can cause the UI to stutter or the VPN to fail silently without proper error bubbling.
- **Actionable Mitigation Path:**
  - Audit all file operations in `lib/services/` and replace any synchronous `existsSync()` or `readAsStringSync()` calls with their asynchronous equivalents (`exists()`, `readAsString()`).
  - Move disk IO operations out of UI thread initialization paths and into isolated background tasks or dedicated initializers that handle errors gracefully and provide UI feedback (e.g., loading states).

## 3. Dependency on External Repositories (Gists)
- **Issue:** The `ConfigGistService` fetches VPN configurations directly from a hardcoded GitHub Gist.
- **Vulnerability:** If the Gist is compromised, malicious configurations (like routing traffic to a malicious proxy) could be injected into all clients. We rely on the security of the GitHub account holding the Gist. There is no cryptographic signature verification on the fetched JSON payloads.
- **Actionable Mitigation Path:**
  - Implement cryptographic signature verification. The server (or a trusted CI pipeline) should sign the Gist payload with a private key. The Flutter app should bundle the corresponding public key and verify the payload signature before parsing and applying the configurations.
  - Consider moving away from Gists to a dedicated API endpoint with TLS pinning and request authentication.

## 4. Unused / Overridden Dependencies
- **Issue:** The project uses several overridden local packages (like `window_manager`, `permission_handler_windows`) via `dependency_overrides`.
- **Vulnerability:** These local versions might fall behind upstream security patches or bug fixes, introducing technical debt and potential vulnerabilities that automated dependency scanners (like Dependabot) won't catch.
- **Actionable Mitigation Path:**
  - Create a ticket to audit the specific patches made in these local overrides. If the patches are no longer necessary, remove the overrides and point to the latest stable versions on pub.dev.
  - If the patches are still required, submit them as Pull Requests to the upstream repositories to get them merged and eventually remove the local overrides.

## 5. Ephemeral Tester and Test Orchestrator
- **Issue:** The testing framework allocates local ports and runs proxy instances to test configs.
- **Vulnerability:** Port exhaustion or zombie processes can occur if a test crashes mid-execution, as cleanup relies on `try/finally` blocks that might be bypassed during a severe isolate crash or OS kill signal.
- **Actionable Mitigation Path:**
  - Implement a resilient process tracking mechanism. Write the PIDs of spawned test proxies to a local temporary file. Implement a startup check that reads this file and forcefully kills any orphaned processes from previous runs before starting new tests.
  - Explore using Dockerized test environments or ephemeral cloud instances for heavy integration testing to ensure complete isolation and reliable cleanup.
