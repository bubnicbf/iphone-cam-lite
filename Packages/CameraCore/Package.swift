// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CameraCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CameraCore", targets: ["CameraCore"])
    ],
    dependencies: [
        .package(name: "Logging", path: "../Logging")
    ],
    targets: [
        .target(
            name: "CameraCore",
            dependencies: [
                .product(name: "Logging", package: "Logging")
            ],
            path: "Sources/CameraCore"
        )
    ]
)
