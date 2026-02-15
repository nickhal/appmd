// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AppMDDemo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "AppMDDemo",
            dependencies: [
                .product(name: "AppMDKit", package: "swift"),
            ],
            path: "Sources"
        ),
    ]
)
