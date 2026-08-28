// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SystemChecks",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SystemChecks", targets: ["SystemChecks"])
    ],
    dependencies: [
        .package(name: "Logging", path: "../Logging")
    ],
    targets: [
        .target(
            name: "SystemChecks",
            dependencies: [
                .product(name: "Logging", package: "Logging")
            ],
            path: "Sources/SystemChecks"
        )
    ]
)
