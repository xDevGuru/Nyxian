# Nyxian External Dependencies & Asset Tracking

This document tracks all external binary dependencies, compiler toolchains, SDKs, and helper binaries required by Nyxian to build in CI and run on device.

---

## 1. Inventory of External Assets

| # | File Name | Self-Hosted Download URL | Size | Purpose |
|---|---|---|---|---|
| **1** | `CoreCompilerSupportLibs.tar.gz.part-aa` | https://github.com/xDevGuru/Nyxian/releases/download/dependencies/CoreCompilerSupportLibs.tar.gz.part-aa | ~128 MB | Prebuilt LLVM/Clang support libraries for CI compilation |
| **2** | `iPhoneOS26.5.sdk.zip` | https://github.com/xDevGuru/Nyxian/releases/download/dependencies/iPhoneOS26.5.sdk.zip | ~32.3 MB | iOS SDK symbol stubs (`.tbd`) and headers for on-device app compilation |
| **3** | `ldid` | https://github.com/xDevGuru/Nyxian/releases/download/dependencies/ldid | ~2.5 MB | ARM64 codesigning tool bundled into the app for on-device Mach-O signing |
| **4** | `TrollStore.tar` | https://github.com/xDevGuru/Nyxian/releases/download/dependencies/TrollStore.tar | ~2.3 MB | Contains `trollstorehelper` used by Nyxian to auto-install `.ipa` to SpringBoard |
| **5** | `theos-runtime.tar.gz` | https://github.com/xDevGuru/Nyxian/releases/download/dependencies/theos-runtime.tar.gz | ~32.4 MB | Theos substrate / tweak development runtime (optional for tweak development) |

---

## 2. Already Pre-Bundled in Git Repository (`Shared/`)

The following assets are already stored directly in the `Nyxian/Shared/` directory of your repository, so they are **100% offline** and do not require external downloads:

* `Shared/lib.zip` — Availability libraries (`@available` runtime checks)
* `Shared/include.zip` — Standard C/Clang system headers (`stdio.h`, `math.h`, `simd`)
* `Shared/swift.zip` — Swift compiler standard library runtime modules
* `Shared/org.emexlabs.rootca.v1.pub.nxt2c` — Public verification RootCA key (119 bytes)

---

## 3. Self-Hosted Release Status

All external dependencies are **100% self-hosted** under your GitHub repository release:
🔗 **https://github.com/xDevGuru/Nyxian/releases/tag/dependencies**
