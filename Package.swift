// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "App",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: ["Yams"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "App",
            dependencies: ["AppCore"],
            resources: [.copy("Resources/WhatsNew"), .process("Resources/Localization")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Automation, self-test and media tools (DevTools/): in debug builds; a release
                // build gets them only with -Xswiftc -DAUTOMATION (scripts/build-app.sh for tests).
                .define("AUTOMATION", .when(configuration: .debug)),
            ],
            linkerSettings: [
                // .build/debug/App runs without an app bundle: an Info.plist inside the binary gives it
                // a bundle id of its own, so its settings do not go to a domain named "App".
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", Context.packageDirectory + "/Packaging/Debug-Info.plist"], .when(configuration: .debug)),
            ]
        ),
        // The logic in AppCore, by area.
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The repository itself: docs and their pictures, scripts, packaging, release notes.
        .testTarget(
            name: "RepoTests",
            dependencies: ["AppCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
