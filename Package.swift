// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Everything",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Everything", targets: ["Everything"]),
        .executable(name: "EverythingTestRunner", targets: ["EverythingTestRunner"]),
        .library(name: "EverythingCore", targets: ["EverythingCore"]),
    ],
    targets: [
        .target(
            name: "EverythingCore",
            path: "Sources/EverythingCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Everything",
            dependencies: ["EverythingCore"],
            path: "Sources/Everything",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "EverythingTestRunner",
            dependencies: ["EverythingCore"],
            path: "Tests/EverythingTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
