// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bugbear",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bugbear", targets: ["Bugbear"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
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
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BugbearCoreTests",
            dependencies: ["BugbearCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
