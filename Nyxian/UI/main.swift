/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.
*/

import UIKit

// Headless CLI interceptor
for (idx, arg) in CommandLine.arguments.enumerated() {
    if arg == "--build" || arg == "--check" || arg == "--clean" || arg == "--doctor" || arg == "--info" {
        let exitCode = NXCommandLineRunner.run(arguments: CommandLine.arguments)
        exit(exitCode)
    }
    if arg == "--help" || arg == "-h" {
        print("Nyxian iOS IDE CLI")
        print("Usage:")
        print("  Nyxian --build <project_path>     Compile, sign, and install project")
        print("  Nyxian --check <project_path>     Fast syntax & typecheck without install")
        print("  Nyxian --clean <project_path>     Purge intermediate project build cache")
        print("  Nyxian --doctor                   Report toolchain & system health (JSON)")
        exit(0)
    }
}

// Normal GUI Launch
_ = UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(AppDelegate.self)
)
