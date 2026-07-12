1. **Analyze the CI Failure:**
   The GitHub Actions logs show that the `flutter-checks` job failed due to `flutter analyze` failing.
   ```
   37 issues found. (ran in 13.7s)
   ```
   The issues include:
   - `info • Statements in an if should be enclosed in a block.` (multiple lines in `lib/screens/connection_home_screen.dart`, `lib/services/config_manager.dart`, `lib/services/native_vpn_service.dart`, `lib/services/singbox_config_generator.dart`, `lib/services/testers/*.dart`, `lib/utils/advanced_logger.dart`)
   - `warning • The value of the local variable 'failedAttempts' isn't used. Try removing the variable or using it • lib/services/smart_pinger.dart:288:11 • unused_local_variable`
   - `info • The private field _isRefreshing could be 'final'. Try making the field 'final' • lib/services/config_manager.dart:211:8 • prefer_final_fields`

   However, my changes were limited to `lib/services/config_manager.dart` and `lib/services/smart_pinger.dart` due to the "Anti-Conflict Rule: STRICTLY limit your changes to `lib/services/config_manager.dart` and `lib/services/smart_pinger.dart`. Do NOT touch UI screens or Singbox generators."

   I will fix the issues strictly inside `lib/services/config_manager.dart` and `lib/services/smart_pinger.dart`.

   Specifically:
   - `lib/services/config_manager.dart`:
     - Add curly braces for `if` statements around lines 465, 467, 475, 477, 495, 497, 505, 507, 597, 599, 732, 734, 936.
     - Make `_isRefreshing` final.
   - `lib/services/smart_pinger.dart`:
     - Remove the unused `failedAttempts` variable around line 288.

2. **Fix `config_manager.dart`**: Add block braces and fix `final`.
3. **Fix `smart_pinger.dart`**: Remove unused variables.
4. **Submit**.
