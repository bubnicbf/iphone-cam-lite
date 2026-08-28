// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Logging",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Logging", targets: ["Logging"])
    ],
    targets: [
        .target(name: "Logging", path: "Sources/Logging")
    ]
)
