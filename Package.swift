// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bugbear",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bugbear", targets: ["Bugbear"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        .target(
            name: "BugbearCore",
            dependencies: ["Yams"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Bugbear",
            dependencies: ["BugbearCore"],
            resources: [.copy("Resources/WhatsNew"), .process("Resources/Localization")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Automation, self-test and media tools (DevTools/): in debug builds; a release
                // build gets them only with -Xswiftc -DAUTOMATION (scripts/build-app.sh for tests).
                .define("AUTOMATION", .when(configuration: .debug)),
            ]
        ),
        // The logic in BugbearCore, by area.
        .testTarget(
            name: "BugbearCoreTests",
            dependencies: ["BugbearCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The repository itself: docs and their pictures, scripts, packaging, release notes.
        .testTarget(
            name: "RepoTests",
            dependencies: ["BugbearCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
