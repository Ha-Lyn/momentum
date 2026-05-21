// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MomentumNative",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "MomentumNative",
            targets: ["MomentumNative"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "MomentumNative"
        ),
    ]
)
