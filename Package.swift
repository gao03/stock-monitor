// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StockMonitorNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "StockMonitorNativeLibrary", targets: ["StockMonitorNative"]),
        .executable(name: "StockMonitorNative", targets: ["StockMonitorNativeApp"])
    ],
    targets: [
        .target(
            name: "StockMonitorNative",
            path: "Sources/StockMonitorNative"
        ),
        .executableTarget(
            name: "StockMonitorNativeApp",
            dependencies: ["StockMonitorNative"],
            path: "Sources/StockMonitorNativeApp",
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "StockMonitorNativeTests",
            dependencies: ["StockMonitorNative"],
            path: "Tests/StockMonitorNativeTests"
        )
    ]
)
