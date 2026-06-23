// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "NeekShot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NeekShot", targets: ["NeekShot"])
    ],
    targets: [
        .executableTarget(
            name: "NeekShot",
            path: "Sources/NeekShot"
        )
    ]
)
