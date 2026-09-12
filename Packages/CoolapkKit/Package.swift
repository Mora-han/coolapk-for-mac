// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoolapkKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "CoolapkKit", targets: ["CoolapkKit"]),
    ],
    targets: [
        .target(
            name: "CoolapkKit",
            path: "Sources/CoolapkKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
