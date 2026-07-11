# Workflows Inventory

This document analyzes the current GitHub workflows in `.github/workflows/` to understand their purpose, potential overlaps, and provides suggestions for keeping, merging, or deleting them.

## 1. `build_core.yml`
- **Purpose:** Compiles the `SagerNet/sing-box` VPN core (`libbox.aar`) from source (Go) using `gomobile` and a specific NDK version, tailored to our project requirements.
- **Overlap:** None. It's an isolated utility workflow.
- **Suggestion:** **Keep.** Crucial for building custom VPN cores when needed.

## 2. `main_pipeline.yml`
- **Purpose:** The primary CI/CD pipeline (`iVPN Final Build`). It triggers on manual dispatch (and potentially pushes/tags) to build the Flutter app for Windows and Android, and then publishes them as GitHub Releases.
- **Overlap:** Heavily overlaps with `build_android_manual.yml` and `build_windows_manual.yml` in terms of steps and output.
- **Suggestion:** **Keep.** This should remain the single source of truth for release builds.

## 3. `pre_pr_checks.yml`
- **Purpose:** Runs static analysis, formatting checks, test suite, and temp file guards on Pull Requests to enforce code health and prevent dirty PRs.
- **Overlap:** Partially overlaps with `test_suite.yml` (since it runs tests).
- **Suggestion:** **Keep.** Essential for project health.

## 4. `test_suite.yml`
- **Purpose:** Likely a standalone workflow to run tests (Flutter test, Dart test).
- **Overlap:** Redundant since `pre_pr_checks.yml` already handles test execution for PRs.
- **Suggestion:** **Merge/Delete.** Unless it runs on different events (like schedules or pushes to main), its logic should be consolidated into `pre_pr_checks.yml` or `main_pipeline.yml`.

## 5. `build_android_manual.yml`
- **Purpose:** A purely manual trigger workflow for building the Android APK. Downloads pre-compiled AARs instead of building the core.
- **Overlap:** 100% overlap with the `build-android` job in `main_pipeline.yml`.
- **Suggestion:** **Delete.** The manual trigger (`workflow_dispatch`) in `main_pipeline.yml` makes this file redundant.

## 6. `build_windows_manual.yml`
- **Purpose:** A purely manual trigger workflow for building the Windows release.
- **Overlap:** 100% overlap with the `build-windows` job in `main_pipeline.yml`.
- **Suggestion:** **Delete.** The manual trigger (`workflow_dispatch`) in `main_pipeline.yml` makes this file redundant.

## 7. `check_android_build.yml`
- **Purpose:** An abbreviated version of the Android build process used as a fast "sanity check" to see if the Android codebase compiles.
- **Overlap:** Partially overlaps with `main_pipeline.yml`.
- **Suggestion:** **Merge/Keep.** Can be integrated into `pre_pr_checks.yml` as an optional dry-run compilation step, or kept as a lightweight manual check if CI minutes are a concern.

## 8. `update.yml`
- **Purpose:** (Need to inspect, but typically used for auto-updating dependencies, pubspec, or version numbers).
- **Overlap:** TBD.
- **Suggestion:** Keep and monitor.

*(Note: These are just suggestions for future cleanup, no workflows have been deleted.)*
