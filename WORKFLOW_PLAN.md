# iVPN CI Workflow Plan

## 1. Objective
Consolidate PR checks and Android build verification while fully securing the VPN Core (`libbox.aar`) supply chain. To achieve minimal CI billable minutes and absolute security, the heavy Go/CGO compilation of the VPN core is decoupled into a dedicated, manually triggered workflow (`build_core.yml`). The main PR pipeline (`pre_pr_checks.yml`) strictly consumes the pre-built, checksum-verified artifacts.

## 2. Decoupled Architecture

### Central Source of Truth: `tool/core_version.txt`
- To prevent hardcoding and ensure synchronization between builder and consumer, a file `tool/core_version.txt` will hold the exact, current release tag expected by the project (e.g., `core-v1.13.14-b1`).
- `pre_pr_checks.yml` will read this file to know exactly which GitHub Release to download from.
- **Workflow Sequence (First-Run)**:
  1. `build_core.yml` is committed and merged into `main`.
  2. The maintainer manually triggers `build_core.yml` via `workflow_dispatch` selecting `all`.
  3. `build_core.yml` builds the AARs, creates the Release (e.g., `core-v1.13.14-b1`), and prints the resulting Tag clearly in its Step Summary. **It does NOT commit directly to `main`** (to respect branch protection rules).
  4. The developer creates a new PR that explicitly updates `tool/core_version.txt` with the new Tag. This PR will run `pre_pr_checks.yml`, automatically pulling the new AAR and verifying it builds successfully before merging.

### Workflow A: `build_core.yml` (The Core Builder)
- **Purpose**: Compile the Sing-box VPN core into Android AARs from official source code securely and publish them as an internal/pre-release GitHub Release asset within the `ivpn_app` repository.
- **Trigger**: Strictly `workflow_dispatch` with required inputs:
  - `singbox_tag`: Required (e.g., `v1.13.14`).
  - `build_scope`: Choice of `all` (default) or `arm64-only`.
- **Environment Pinning (Reproducibility)**:
  - **Go**: Pinned explicitly to `1.21.x` (or exact matching version for sing-box).
  - **NDK**: Pinned exactly to `28.2.13676358` (which aligns with the current Flutter stable ecosystem).
- **Build Logic**:
  1. Clone `SagerNet/sing-box` at the `singbox_tag`.
  2. Setup Java, pinned Go, and pinned Android SDK/NDK.
  3. Install `gomobile` based on the official sing-box requirements.
  4. Conditional Compilation based on `build_scope`:
     - **If `all`**: Runs `go run ./cmd/internal/build_libbox -target android` (which produces both `libbox.aar` and `libbox-legacy.aar`). Release tag format: `core-<singbox_tag>-<build_number>`.
     - **If `arm64-only`**: Runs `go run ./cmd/internal/build_libbox -target android -platform=android/arm64`. Release tag format: `core-<singbox_tag>-arm64-test`.
  5. Generate a SHA256 checksum file (`aar_checksums.txt`) dynamically containing hashes of all produced `.aar` files.
  6. Create a GitHub Release in the `ivpn_app` repo using the designated tag and upload the `.aar` files along with the `aar_checksums.txt`.

### Workflow B: `pre_pr_checks.yml` (The Consumer)
- **Purpose**: Fast, efficient PR verification enforcing strict quality gates.
- **Trigger**: `pull_request` (branches: main) and `workflow_dispatch`.
- **CRITICAL ARCHITECTURE RULE**: The PR pipeline MUST ALWAYS read from `tool/core_version.txt` and verify it does **NOT** contain `-test` or `-arm64-test` in the string. If a developer accidentally points the codebase to an arm64-only test build, the PR pipeline must fail immediately to prevent pushing an incompatible universal app bundle to users.
  ```yaml
  steps:
    - name: Validate Core Tag
      run: |
        TAG=$(cat tool/core_version.txt | xargs)
        echo "Using tag: $TAG"
        if [[ "$TAG" == *"-test"* ]]; then
          echo "ERROR: Refusing to build PR with a test core tag ($TAG)."
          exit 1
        fi
        echo "CORE_RELEASE_TAG=$TAG" >> $GITHUB_ENV
  ```
- **Jobs**:
  1. **`changes`**: Path filtering (`dorny/paths-filter@v3`).
  2. **`temp-files-guard`**: Fast check for `.bak`, `*patch*`, etc.
  3. **`flutter-checks`**: Formatting, Analyzer, Tests.
  4. **`android-lint`**: Strict Kotlin linting (`ktlint`).
  5. **`android-build`**:
     - **Validation**: Executes the "Validate Core Tag" step directly as the VERY FIRST step in this job, before any fetching.
     - **Setup**: JDK, Gradle caching (`setup-gradle@v3`).
     - **AAR Fetching**:
       - Uses the validated tag from `CORE_RELEASE_TAG`.
       - Downloads `libbox.aar`, `libbox-legacy.aar`, and `aar_checksums.txt` from the specified GitHub Release tag.
       - Terminal dependencies remain pinned to JitPack `v0.118.3`.
     - **Verification**: Runs `sha256sum --strict --check ../../../tool/aar_checksums.txt` from `android/app/libs` to guard against transfer corruption or release tampering.
     - **Build**: Runs `flutter build appbundle --debug` to ensure ABI-split compatibility and code integrity.
  6. **`pr-summary`**: Final aggregator to prevent silent passes on skipped/failed jobs.

## 3. Dependency Graph (pre_pr_checks.yml)

```text
       [ changes ]        [ temp-files-guard ]
        /         \               |
       /           \              |
[ flutter-checks ] [ android-lint ]
       \           /              |
        \         /               |
      [ android-build ]           |
              \                  /
               \                /
                 [ pr-summary ]
```

## 4. Advanced Caching & Speed
- **AAR Caching in PRs**:
  - Since we pull from a fixed internal release tag stored in `tool/core_version.txt`, the cache key becomes highly deterministic: `${{ runner.os }}-aar-internal-${{ hashFiles('tool/core_version.txt') }}`.
  - This ensures downloading from GitHub Releases only happens once per core update. Subsequent PRs restore the AAR and checksum instantly from cache.
- **Gradle Caching**: Handled natively by `gradle/actions/setup-gradle@v3`.
- **Flutter Caching**: Handled natively by `subosito/flutter-action@v2`.

## 5. Estimated Execution Times

| Scenario | Conditions | Estimated Time |
| :--- | :--- | :--- |
| **Core Build (`build_core.yml`)** | Manual trigger, builds 4 ABIs via Gomobile | ~10 - 15 mins (One-off) |
| **PR - Absolute Best (Skipped)** | Only Markdown or Docs changed | ~30s |
| **PR - Typical Best (Warm Cache)**| Code changed, but AARs & Gradle cache hit | ~3 - 4 mins |
| **PR - Worst Case (Cold Cache)** | Cache miss, downloads internal Release, Gradle sync | ~6 - 9 mins |