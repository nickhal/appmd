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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
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
    ]
)
