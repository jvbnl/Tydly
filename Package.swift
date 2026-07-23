// swift-tools-version: 6.2
import PackageDescription

// Tydly — a local, trust-earning file archivist that lives in the macOS menu bar.
//
// Four targets, deliberately:
//   • TydlyCore  — pure Foundation. Domain model + the rule-enforcement logic for the
//                  ten non-negotiable product rules. No SwiftUI, AppKit, or Combine, so
//                  it stays unit-testable and portable to other platforms later.
//   • TydlyAI    — the constrained, fully local Foundation Models adapter. It can rank
//                  allowlisted projects but has no filesystem or networking capabilities.
//   • TydlyPersistence — the encrypted SQLCipher operation ledger and Keychain key store.
//   • Tydly      — the macOS executable. SwiftUI `MenuBarExtra` + a thin AppKit
//                  `AppDelegate` for the onboarding window.
//
// Built and run entirely from the command line (see the Makefile) — no Xcode project.
let package = Package(
    name: "Tydly",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26) // Foundation Models requires macOS 26 and Apple Intelligence hardware.
    ],
    products: [
        .executable(name: "Tydly", targets: ["Tydly"]),
        .library(name: "TydlyCore", targets: ["TydlyCore"]),
        .library(name: "TydlyAI", targets: ["TydlyAI"]),
        .library(name: "TydlyPersistence", targets: ["TydlyPersistence"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sqlcipher/GRDB.swift.git",
            exact: "7.11.1"
        ),
        .package(
            url: "https://github.com/sqlcipher/SQLCipher.swift.git",
            exact: "4.17.0"
        )
    ],
    targets: [
        .target(
            name: "TydlyCore"
        ),
        .target(
            name: "TydlyAI",
            dependencies: ["TydlyCore"]
        ),
        .target(
            name: "TydlyPersistence",
            dependencies: [
                "TydlyCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "Tydly",
            dependencies: ["TydlyCore", "TydlyAI"],
            // Info.plist / entitlements live beside the sources but are not Swift sources
            // or bundle resources — the linker flag below embeds the plist, and the app
            // bundle script copies both. Excluding them keeps `swift build` warning-free.
            exclude: [
                "Info.plist",
                "Tydly.entitlements"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // Embed Info.plist directly into the executable so `swift run` launches
                // Tydly as a menu-bar agent (LSUIElement) without a bundled .app.
                // Path is resolved relative to the package root at build time.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Tydly/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "TydlyCoreTests",
            dependencies: ["TydlyCore"]
        ),
        .testTarget(
            name: "TydlyAITests",
            dependencies: ["TydlyAI", "TydlyCore"]
        ),
        .testTarget(
            name: "TydlyPersistenceTests",
            dependencies: ["TydlyPersistence", "TydlyCore"]
        )
    ]
)
