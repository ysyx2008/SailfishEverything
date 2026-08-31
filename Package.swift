// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Everything",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Everything",
            path: "Sources/Everything",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
