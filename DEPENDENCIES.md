# Nyxian External Dependencies & Asset Tracking

This document tracks all external binary dependencies, compiler toolchains, SDKs, and helper binaries required by Nyxian to build in CI and run on device.

---

## 1. Inventory of External Assets

| # | File Name | Direct Download URL | Size | Purpose |
|---|---|---|---|---|
| **1** | `CoreCompilerSupportLibs.tar.gz.part-aa` | https://github.com/SuSuDear/emexDE/releases/download/v1.0.0/CoreCompilerSupportLibs.tar.gz.part-aa | ~294 MB | Prebuilt LLVM/Clang support libraries for CI compilation |
| **2** | `iPhoneOS26.5.sdk.zip` | https://nyxian.app/bootstrap/iPhoneOS26.5.sdk.zip | ~34.8 MB | iOS SDK symbol stubs (`.tbd`) and headers for on-device app compilation |
| **3** | `ldid` | https://github.com/opa334/ldid/releases/latest/download/ldid | ~1.9 MB | ARM64 codesigning tool bundled into the app for on-device Mach-O signing |
| **4** | `TrollStore.tar` | https://github.com/opa334/TrollStore/releases/latest/download/TrollStore.tar | ~1.1 MB | Contains `trollstorehelper` used by Nyxian to auto-install `.ipa` to SpringBoard |
| **5** | `theos-runtime.tar.gz` | https://github.com/SuSuDear/emexDE/releases/download/theos-runtime/theos-runtime.tar.gz | ~32.4 MB | Theos substrate / tweak development runtime (optional for tweak development) |

---

## 2. Already Pre-Bundled in Git Repository (`Shared/`)

The following assets are already stored directly in the `Nyxian/Shared/` directory of your repository, so they are **100% offline** and do not require external downloads:

* `Shared/lib.zip` — Availability libraries (`@available` runtime checks)
* `Shared/include.zip` — Standard C/Clang system headers (`stdio.h`, `math.h`, `simd`)
* `Shared/swift.zip` — Swift compiler standard library runtime modules
* `Shared/org.emexlabs.rootca.v1.pub.nxt2c` — Public verification RootCA key (119 bytes)

---

## 3. Migration Plan to Self-Host Under `xDevGuru/Nyxian`

Once you upload the files to your GitHub repository:

1. Create a release tag on GitHub: `v1.0-assets` under `https://github.com/xDevGuru/Nyxian/releases`.
2. Upload the 5 files above as release assets.
3. Update `.github/workflows/build.yml` and `Makefile` to download from:
   `https://github.com/xDevGuru/Nyxian/releases/download/v1.0-assets/<filename>`
