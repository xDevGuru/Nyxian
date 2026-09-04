# Nyxian iOS 17.0 + TrollStore Patch Notes & Rebase Guide

This document maintains a complete, chronological record of all custom modifications, architectural decisions, user preferences, and patch recipes applied to this fork (`xDevGuru/Nyxian`).

> **Target Device**: iPhone XS (A12 Bionic)  
> **Target OS**: iOS 17.0  
> **Deployment Method**: TrollStore (unsandboxed + root privileges)  
> **Upstream Repository**: `emexlab/Nyxian` (synced at `0.11.4` / commit `edfa5c37`)  
> **Reference Fork**: `SuSuDear/emexDE` (`SuCode`)

---

## 1. User Preferences & Design Philosophy

1. **No In-IDE App Running**:
   - The user does **NOT** want or need apps running inside the IDE (no internal microkernel window server / LiveContainer / `PEProcessManager` guest process needed).
   - In-IDE app running adds heavy overhead on an iPhone XS (A12, 4GB RAM) and introduces unnecessary iOS 18+ virtualization/microkernel dependencies.
2. **On-Device Build & External Run (TrollStore Workflow)**:
   - The IDE is strictly for:
     1. Browsing and editing code (Swift, C, ObjC, C++).
     2. Compiling on-device with the native toolchain (`MDKDriver`, `clang`, `swiftc`).
     3. Tapping **Run** -> Signs executable via bundled `ldid` -> Packages `.ipa` -> Automatically installs directly to iOS SpringBoard via TrollStore -> Automatically opens the app.
3. **Future Upstream Sync Capability**:
   - When upstream releases new updates, all custom patches in this document can be quickly re-applied on top of the newly synced upstream main in a single clean commit.

---

## 2. Summary of Patches Applied

| Component | File | Summary of Change |
| :--- | :--- | :--- |
| **Deployment Target** | `Nyxian.xcodeproj/project.pbxproj` | Lowered `IPHONEOS_DEPLOYMENT_TARGET` from `18.4` to `17.0` for all targets. |
| **Kext Validation** | `Nyxian/LindChain/ProcEnvironment/KextLoader/PEKext.m` | Lowered `ksurfaceMainKext` minimum OS check from `18.4.0` to `16.0.0`. |
| **Clang Target** | `Nyxian/LindChain/ProcEnvironment/Surface/shimcache/shimcache.m` | Changed hardcoded compiler target from `apple-arm64-ios18.4` to `apple-arm64-ios17.0`. |
| **TPRO Hardware Guards** | `LCBootstrap.m` & `Tweaks/Dyld.m` | Replaced `assert(os_tpro_is_supported())` with safe `if (os_tpro_is_supported())` checks to prevent crashes on non-TPRO chips (A12-A17). |
| **TrollStore Support Subsystem** | `Nyxian/LindChain/TrollStoreSupport/` | Added `NXTrollStoreSupport.h` and `.m` (spawn root, sign via ldid, install via trollstorehelper, launch via LSApplicationWorkspace). |
| **Swift Bridging** | `Nyxian/NXBridge.h` | Exposed `NXTrollStoreSupport.h` to Swift. |
| **Builder Run Pipeline** | `Nyxian/LindChain/IDEBuilder/NXBuilder.swift` | In `install(...)`, replaced sandbox container install with `signExecutable` + `package` + `installIpa` + `openApplication`. Pre-sign exported IPAs. |
| **Run UI Actions** | `FileList.swift` & `FileList+iPad.swift` | Bypassed `PEProcessManager.shared().spawnProcess` for app targets since TrollStore installs and opens natively. |
| **TrollStore Entitlements** | `supports/Nyxian.entitlements.plist` | Added unsandboxed + root entitlements (`no-sandbox`, `persona-mgmt`, `canmaplsdatabase`, `MobileContainerManager.allowed`). |
| **ldid Entitlements** | `supports/ldid.entitlements.plist` | Added `platform-application`, `no-container`, `storage.AppDataContainers`. |
| **Root Binaries Registration** | `Info.plist` | Added `trollstorehelper` and `ldid` to `TSRootBinaries` array. |
| **Packaging Pipeline** | `Makefile` | Bundles `ldid` + `trollstorehelper`, fake-signs `Nyxian.app` with root entitlements during packaging. |
| **CI / GitHub Actions** | `.github/workflows/build.yml` | Fixed `upload-artifact` from invalid `@v7` to official `@v4`. |

---

## 3. Detailed Patch Recipes (For Re-Syncing)

If you pull a fresh update from `emexlab/Nyxian:main`, apply the following changes:

### Patch 1: Project Deployment Target (`Nyxian.xcodeproj/project.pbxproj`)
Find all occurrences of:
```
IPHONEOS_DEPLOYMENT_TARGET = 18.4;
```
Replace with:
```
IPHONEOS_DEPLOYMENT_TARGET = 17.0;
```

### Patch 2: Microkernel Dependency Version Check (`PEKext.m`)
In `+ (instancetype)ksurfaceMainKext`:
```objc
// Change:
dependency.minVersion = @"18.4.0";
// To:
dependency.minVersion = @"16.0.0";
```

### Patch 3: Shimcache Compiler Target (`shimcache.m`)
In `ksurface_shimcache_build`:
```objc
// Change:
[driverFlags addObject:@"apple-arm64-ios18.4"];
// To:
[driverFlags addObject:@"apple-arm64-ios17.0"];
```

### Patch 4: Safe TPRO Hardware Handling (`LCBootstrap.m` & `Dyld.m`)
In `LCBootstrap.m` (around line 70-80) and `Dyld.m` (around line 235-255):
```objc
// Replace:
assert(os_tpro_is_supported());
os_thread_self_restrict_tpro_to_rw();

// With:
if (os_tpro_is_supported()) {
    os_thread_self_restrict_tpro_to_rw();
}
```
And for `os_thread_self_restrict_tpro_to_ro`:
```objc
if (ret != KERN_SUCCESS && os_tpro_is_supported()) {
    os_thread_self_restrict_tpro_to_ro();
}
```

### Patch 5: Add `NXTrollStoreSupport` Files
Ensure the directory `Nyxian/LindChain/TrollStoreSupport/` contains:
- `NXTrollStoreSupport.h`
- `NXTrollStoreSupport.m`

Include in `Nyxian/NXBridge.h`:
```objc
#import <LindChain/TrollStoreSupport/NXTrollStoreSupport.h>
```

### Patch 6: Update `NXBuilder.swift` App Installation
In `NXBuilder.install(buildType:executablePathCallback:)`:
Replace the `if self.project.projectConfig.schemeKind == .app` block with:
```swift
if self.project.projectConfig.schemeKind == .app {
    do {
        let entitlementsPath = try NXTrollStoreSupport.projectEntitlementsPath(forProjectPath: self.project.url.path)
        try NXTrollStoreSupport.signExecutable(atPath: self.project.machoURL.path, entitlementsPath: entitlementsPath)
        try self.package()
        if buildType == .run {
            try NXTrollStoreSupport.installIpa(atPath: self.project.packageURL.path)
            try NXTrollStoreSupport.openApplication(withBundleIdentifier: self.project.projectConfig.bundleid)
        }
    } catch {
        throw NSError(domain: "org.emexlabs.nyxian.builder.install", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
    }
}
```
And in the `export` branch, pre-sign with ldid:
```swift
if self.project.projectConfig.schemeKind == .app {
    if let entitlementsPath = try? NXTrollStoreSupport.projectEntitlementsPath(forProjectPath: self.project.url.path) {
        try? NXTrollStoreSupport.signExecutable(atPath: self.project.machoURL.path, entitlementsPath: entitlementsPath)
    }
    try self.package()
}
```

### Patch 7: Update Run Action in `FileList.swift` and `FileList+iPad.swift`
- In `FileList.swift`:
  For `.app` projects, directly call:
  ```swift
  buildProjectWithArgumentUI(targetViewController: self, project: project, buildType: .run)
  ```
  without spawning via `PEProcessManager`.
- In `FileList+iPad.swift`:
  Remove `PEProcessManager.shared().spawnProcess` for `.app` projects so only `.utility` projects use the terminal session.

### Patch 8: TrollStore Entitlements & Packaging
1. Place `supports/Nyxian.entitlements.plist` and `supports/ldid.entitlements.plist` in the repo root.
2. In `Info.plist`, ensure `TSRootBinaries` contains:
   ```xml
   <key>TSRootBinaries</key>
   <array>
       <string>trollstorehelper</string>
       <string>ldid</string>
       <string>tshelper</string>
   </array>
   ```
3. In `Makefile`, update `package-app`:
   ```makefile
   package-app:
   	cp -r  build/Nyxian.xcarchive/Products/Applications Payload
   	@if [ ! -d Payload/Nyxian.app ]; then \
   		echo "No Nyxian app bundle found in Payload"; exit 1; \
   	fi
   	curl -L https://github.com/opa334/ldid/releases/latest/download/ldid -o Payload/Nyxian.app/ldid
   	chmod 0755 Payload/Nyxian.app/ldid
   	echo bundled > Payload/Nyxian.app/ldid.version
   	chmod 0644 Payload/Nyxian.app/ldid.version
   	curl -sL https://github.com/opa334/TrollStore/releases/latest/download/TrollStore.tar -o tmp_trollstore.tar
   	tar -xf tmp_trollstore.tar TrollStore.app/trollstorehelper
   	cp TrollStore.app/trollstorehelper Payload/Nyxian.app/trollstorehelper
   	rm -rf tmp_trollstore.tar TrollStore.app
   	chmod 0755 Payload/Nyxian.app/trollstorehelper
   	ldid -Ssupports/Nyxian.entitlements.plist Payload/Nyxian.app
   	ldid -Ssupports/ldid.entitlements.plist Payload/Nyxian.app/ldid
   	-rm $(FILE)
   	zip -r $(FILE) ./Payload
   ```
4. In `.github/workflows/build.yml`:
   Ensure `actions/upload-artifact@v4` is used.

---

## 4. Next Steps & Planned Optimizations

1. **Test Initial Build on iPhone XS (iOS 17.0)**:
   - Install the generated `Nyxian.ipa` via TrollStore.
   - Verify on-device launch and project creation.
   - Test "Run" on a simple Swift / ObjC app template: verify that `ldid` signs the app, TrollStore automatically installs it to the Home Screen, and the app opens.
2. **Further Trimming of Unused In-IDE Microkernel Code (Optional)**:
   - If memory footprint on iPhone XS (4GB RAM) needs optimization, we can disable or remove the guest process manager (`LiveProcess`), the in-app window tiling server (`NXWindowServer`), and internal kextloader during IDE runtime, keeping only the editor and compiler toolchain active.
3. **UI Enhancements from SuSuDear / emexDE**:
   - Keyboard accessory improvements (caret visibility, selection scroll).
   - Localization strings.
   - App icon picker for created projects.
