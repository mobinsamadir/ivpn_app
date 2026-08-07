1. **Analyze Requirements:**
   - Role: Hunter (Security Auditor)
   - Scope: `lib/services/`
   - Frozen Zones: `android/`
   - Task: Review security and fix config leaks.
   - Golden Rule: Apply Phase 1 and Phase 2.

2. **Phase 2 Code Fixes:**
   - In `lib/services/native_vpn_service.dart`, config files are created but not deleted correctly. They are only deleted in `catch` blocks. We need to delete them in `finally` blocks to prevent `Information Disclosure`.
   - The files are:
     - `ping_config_...` in `getPing`
     - `test_proxy_...` in `startTestProxy`
     - `vpn_config_...` in `connect`
   - In `lib/services/windows_vpn_service.dart`, `_currentConfigPath` is not set during `startVpn`. It's only declared and read in `stopVpn`. We need to assign `_currentConfigPath = configFile.path` when `configFile` is created.

3. **Bash Commands to Execute Fixes:**
   - Modify `native_vpn_service.dart`: Replace `catch` blocks with `finally` blocks for `tempFile` deletion.
   - Modify `windows_vpn_service.dart`: Assign `_currentConfigPath = configFile.path`.

4. **Verify:**
   - Run tests (`flutter test`)
   - Check if any changes broke tests.

5. **Pre Commit & Submit:**
   - Write report in `my-home/scouts/1_hunter_log.md`
   - Write in `my-home/CHAT.md`
   - Commit files in `lib/services/` and `my-home/`
   - Run pre-commit instructions
   - Push / Submit
