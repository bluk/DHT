// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "DHT",
    products: [
        .library(
            name: "DHT",
            targets: ["DHT"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/bluk/btmetainfo.git", .upToNextMajor(from: "0.1.1")),
    ],
    targets: [
        .target(
            name: "DHT",
            dependencies: ["BTMetainfo"]
        ),
        .testTarget(
            name: "DHTTests",
            dependencies: ["DHT"]
        ),
    ]
)
