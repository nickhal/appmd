// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "appmd-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppMDKit",
            targets: ["AppMDKit"]
        ),
        .plugin(
            name: "AppMDPlugin",
            targets: ["AppMDPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "AppMDKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "AppMDKitTests",
            dependencies: ["AppMDKit"]
        ),

        // Build plugin: generates AppMDModel conformance from _schema.yaml
        .plugin(
            name: "AppMDPlugin",
            capability: .buildTool(),
            dependencies: ["appmd-codegen"],
            path: "Plugins/AppMDPlugin"
        ),

        // Code generator executable (invoked by the plugin)
        .executableTarget(
            name: "appmd-codegen",
            path: "Sources/AppMDCodeGen"
        ),

        // CLI tool
        .executableTarget(
            name: "appmd-cli",
            dependencies: [
                "AppMDKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AppMDCLI"
        ),
    ]
)
