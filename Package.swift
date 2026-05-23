// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StockMonitorNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StockMonitorNative", targets: ["StockMonitorNative"])
    ],
    targets: [
        .executableTarget(
            name: "StockMonitorNative",
            path: "Sources/StockMonitorNative"
        ),
        .testTarget(
            name: "StockMonitorNativeTests",
            dependencies: ["StockMonitorNative"],
            path: "Tests/StockMonitorNativeTests"
        )
    ]
)
