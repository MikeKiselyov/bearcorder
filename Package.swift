// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QAHelper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QAHelper", targets: ["QAHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "QAHelperCore",
            dependencies: ["Yams"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "QAHelper",
            dependencies: ["QAHelperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "QAHelperCoreTests",
            dependencies: ["QAHelperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
