// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MomentumNative",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "MomentumNative",
            targets: ["MomentumNative"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .executableTarget(
            name: "MomentumNative",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
    ]
)
