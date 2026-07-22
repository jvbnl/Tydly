// swift-tools-version: 5.9
import PackageDescription

// Tydly — a local, trust-earning file archivist that lives in the macOS menu bar.
//
// Two targets, deliberately:
//   • TydlyCore  — pure Foundation. Domain model + the rule-enforcement logic for the
//                  ten non-negotiable product rules. No SwiftUI, AppKit, or Combine, so
//                  it stays unit-testable and portable to other platforms later.
//   • Tydly      — the macOS executable. SwiftUI `MenuBarExtra` + a thin AppKit
//                  `AppDelegate` for the onboarding window. Depends on TydlyCore.
//
// Built and run entirely from the command line (see the Makefile) — no Xcode project.
let package = Package(
    name: "Tydly",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13) // MenuBarExtra requires macOS 13 (Ventura).
    ],
    products: [
        .executable(name: "Tydly", targets: ["Tydly"]),
        .library(name: "TydlyCore", targets: ["TydlyCore"])
    ],
    targets: [
        .target(
            name: "TydlyCore"
        ),
        .executableTarget(
            name: "Tydly",
            dependencies: ["TydlyCore"],
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
        )
    ]
)
