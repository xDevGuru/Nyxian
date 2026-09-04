/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.
*/

import Foundation
import MobileDevelopmentKit

@objc public final class NXCommandLineRunner: NSObject {
    @objc public static func run(arguments: [String]) -> Int32 {
        print("[Nyxian CLI] Initializing headless build runner...")

        var targetProjectPath: String? = nil
        for (index, arg) in arguments.enumerated() {
            if arg == "--build" && index + 1 < arguments.count {
                targetProjectPath = arguments[index + 1]
                break
            }
        }

        guard let rawPath = targetProjectPath else {
            print("[Nyxian CLI ERROR] Missing project path. Usage: Nyxian --build <project_path>")
            return 1
        }

        // Resolve path: if relative or UUID, resolve inside projects directory
        let resolvedURL: URL
        if rawPath.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: rawPath)
        } else {
            resolvedURL = NXBootstrap.shared().projectsURL.appendingPathComponent(rawPath)
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            print("[Nyxian CLI ERROR] Project path does not exist: \(resolvedURL.path)")
            return 1
        }

        print("[Nyxian CLI] Loading project from: \(resolvedURL.path)")
        guard let project = NXProject(url: resolvedURL) else {
            print("[Nyxian CLI ERROR] Failed to instantiate NXProject for: \(resolvedURL.path)")
            return 1
        }

        project.projectConfig.reloadData()
        let displayName = project.projectConfig.displayName ?? resolvedURL.lastPathComponent
        let bundleID = project.projectConfig.bundleid ?? "unknown"
        let targetOS = project.projectConfig.deploymentTarget ?? "unknown"

        print("[Nyxian CLI] Target Name:      \(displayName)")
        print("[Nyxian CLI] Bundle ID:        \(bundleID)")
        print("[Nyxian CLI] Deployment Target: \(targetOS)")
        print("[Nyxian CLI] Scheme Kind:      \(project.projectConfig.schemeKind)")

        if !NXBootstrap.shared().isNewest() {
            print("[Nyxian CLI] Initializing bootstrap...")
            NXBootstrap.shared().bootstrap()
        }
        print("[Nyxian CLI] Checking bootstrap components...")
        NXBootstrap.shared().waitTillDone()

        guard let builder = NXBuilder(project: project) else {
            print("[Nyxian CLI ERROR] Failed to initialize NXBuilder.")
            return 1
        }

        do {
            print("[Nyxian CLI] Verifying system requirements...")
            try builder.headsup(buildType: .run)

            print("[Nyxian CLI] Cleaning build cache...")
            try builder.clean()

            print("[Nyxian CLI] Preparing bundle payload and Info.plist...")
            try builder.prepare()

            print("[Nyxian CLI] Compiling source files...")
            try builder.build()

            if project.projectConfig.schemeKind == .app {
                print("[Nyxian CLI] Signing Mach-O binary with ldid...")
                let entitlementsPath = try NXTrollStoreSupport.projectEntitlementsPath(forProjectPath: project.url.path)
                try NXTrollStoreSupport.signExecutable(atPath: project.machoURL.path, entitlementsPath: entitlementsPath)

                print("[Nyxian CLI] Packaging .ipa...")
                try builder.package()

                print("[Nyxian CLI] Installing IPA via trollstorehelper...")
                try NXTrollStoreSupport.installIpa(atPath: project.packageURL.path)
                print("[Nyxian CLI SUCCESS] Application compiled, signed and installed successfully!")
            }

            builder.database.saveDatabase(toPath: project.cacheURL.appendingPathComponent("debug.json").path)
            return 0
        } catch {
            print("[Nyxian CLI BUILD FAILED] \(error.localizedDescription)")
            builder.database.saveDatabase(toPath: project.cacheURL.appendingPathComponent("debug.json").path)

            for (title, obj) in builder.database.debugObjects {
                for item in obj.debugItems {
                    if item.severity == .warning || item.severity == .error || item.severity == .fatal {
                        let line = item.sourceLocation.line
                        let col = item.sourceLocation.column
                        let prefix = (item.severity == .warning) ? "[COMPILER_WARNING]" : "[COMPILER_ERROR]"
                        print("\(prefix) \(title):\(line):\(col): \(item.message)")
                    }
                }
            }
            return 1
        }
    }
}
