# VPN Core Build Notes

## Overview
This document outlines the specific build requirements and dependencies for compiling the VPN core (based on `SagerNet/sing-box`) for our project. It serves as a historical record and a guide for future updates to avoid build errors (like linker relocation errors, e.g., `unknown relocation type 315` in `libcronet.a`).

## Official SagerNet CI Dependencies
Based on our research into the official `SagerNet/sing-box` repository (tag `v1.13.14`), the correct dependencies for a successful Android AAR build are:

- **Go Version:** `~1.25.10`
- **NDK Version:** `r28`
- **Java:** `openjdk-17-jdk-headless`
- **gomobile & gobind Version:** `v0.1.12` (Note: **DO NOT** run `gomobile init`. The official Makefile simply installs the binaries).
- **Checkout Config:** `fetch-depth: 0` and `submodules: 'recursive'` are required during code checkout to ensure all tags and submodules are correctly resolved.

### Critical Environment Variables
During the `build_libbox` execution, the official CI strictly passes the `ANDROID_NDK_HOME` environment variable to ensure the correct NDK toolchain is utilized:
```yaml
env:
  ANDROID_NDK_HOME: ${{ steps.setup-ndk.outputs.ndk-path }}
```

---

## ⚠️ Warning for Future Updates ⚠️
**Whenever upgrading the `SagerNet/sing-box` core to a new release tag, you MUST verify their official CI scripts.**
Do not assume that the current versions of Go, NDK, or `gomobile` will remain compatible. Failing to update these dependencies to match the official repo will likely result in Cgo linker or compilation errors.

### Official Reference Links:
When updating, always review these files in the target tag of the `SagerNet/sing-box` repository:
- **Build Workflow:** [.github/workflows/build.yml](https://github.com/SagerNet/sing-box/blob/main/.github/workflows/build.yml) (Look for `build_android` or similar jobs)
- **Makefile:** [Makefile](https://github.com/SagerNet/sing-box/blob/main/Makefile) (Look for `lib_install` and `lib_android` targets to see exact `gomobile` versions and commands)
- **Go Mod:** [go.mod](https://github.com/SagerNet/sing-box/blob/main/go.mod)
