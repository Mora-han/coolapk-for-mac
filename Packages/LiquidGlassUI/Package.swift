// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidGlassUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LiquidGlassUI", targets: ["LiquidGlassUI"]),
    ],
    targets: [
        .target(
            name: "LiquidGlassUI",
            path: "Sources/LiquidGlassUI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
