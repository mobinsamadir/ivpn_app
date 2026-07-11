# SagerNet/sing-box Tooling Notes

This document captures potential tools, workflows, and test strategies discovered in the `SagerNet/sing-box` repository that could be beneficial for the `ivpn_app` project in the future.

## 1. Versioning & Release Tooling (`cmd/internal/`)
The sing-box repository uses custom Go scripts instead of standard bash scripts for their release lifecycle. These can be found in `cmd/internal/`:
- **`update_android_version` / `update_apple_version`:** Go scripts that dynamically read git tags, generate version codes, and update Android's `version.properties` or Apple's Plist files for CI. This is more robust than simple bash `grep`/`sed` and handles nightly builds.
- **`app_store_connect`:** A custom tool to handle TestFlight and App Store Connect publishing directly from CI.

**Potential value for us:** We could migrate our `tool/update_version.dart` to be more robust, directly mirroring how SagerNet handles dynamic version generation for AARs.

## 2. Advanced Makefile Orchestration
The `Makefile` in sing-box is highly organized and contains targets for formatting, linting, protocol generation, and testing across platforms.
- **`lint` target:** They run `golangci-lint` with specific OS environments (`GOOS=linux`, `GOOS=android`, `GOOS=windows`) to ensure platform-specific code (like tun handlers) is statically analyzed properly.

**Potential value for us:** If we ever modify the Go core directly, adopting their `lint` strategy ensures we don't break platform-specific bindings.

## 3. Testing Strategy (`test/` & `tags`)
- **Integration Tests:** The `test/` directory contains tests that actually spin up proxies and verify traffic.
- **Build Tags (`force_stdio`):** They have a specific `make test_stdio` target that runs tests with `-tags "$(TAGS_TEST),force_stdio"`. This is extremely useful for debugging e2e data streams without complex UI or network stack overhead.

**Potential value for us:** We currently lack deep integration tests for the VPN tunnel itself. We could extract and adapt some of their raw `go test` integration logic to verify our generated `.json` configurations against a mock sing-box binary in our Dart tests.

## 4. Lightweight / Debug Build Scripts
- **Feature Toggles via `build_libbox/main.go`:** The `cmd/internal/build_libbox` script dynamically builds an `AndroidBuildConfig` and injects tags. They explicitly build a "legacy" AAR (API 21) that strips out `with_naive_outbound` to reduce binary size.

**Potential value for us:** If our APK size becomes an issue, we can modify our `build_core.yml` to instruct `build_libbox` to drop unnecessary modules (e.g., if we don't use `naive`, `gvisor`, or `wireguard` in our app, we can remove them from `sharedTags` in `main.go` before building).

## 5. Dependency Management Workflow
- **`stale.yml` & `lint.yml`:** They use GitHub actions to automatically mark stale issues and enforce linting rules strictly.

**Potential value for us:** Adopting a strict linting pipeline for our Dart code (`flutter analyze`) via an action similar to their `lint.yml` would ensure code health.