// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SailfishEverything",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SailfishEverything", targets: ["SailfishEverything"]),
        .executable(name: "SailfishEverythingTests", targets: ["SailfishEverythingTests"]),
        .library(name: "SailfishEverythingCore", targets: ["SailfishEverythingCore"]),
    ],
    targets: [
        .target(
            name: "SailfishEverythingCore",
            path: "Sources/SailfishEverythingCore",
            exclude: ["SPEC.md"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "SailfishEverything",
            dependencies: ["SailfishEverythingCore"],
            path: "Sources/SailfishEverything",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Quartz"),
            ]
        ),
        .executableTarget(
            name: "SailfishEverythingTests",
            dependencies: ["SailfishEverythingCore"],
            path: "Tests/SailfishEverythingTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
