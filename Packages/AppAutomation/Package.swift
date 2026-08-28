// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppAutomation",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AppAutomationCore", targets: ["AppAutomationCore"]),
        .library(name: "ZoomAdapter", targets: ["ZoomAdapter"]),
        .library(name: "TeamsAdapter", targets: ["TeamsAdapter"])
    ],
    dependencies: [
        .package(name: "Logging", path: "../Logging"),
        .package(name: "CameraCore", path: "../CameraCore")
    ],
    targets: [
        .target(
            name: "AppAutomationCore",
            dependencies: [
                .product(name: "Logging", package: "Logging"),
                .product(name: "CameraCore", package: "CameraCore")
            ],
            path: "Sources/AppAutomationCore"
        ),
        .target(
            name: "ZoomAdapter",
            dependencies: [
                "AppAutomationCore",
                .product(name: "Logging", package: "Logging"),
                .product(name: "CameraCore", package: "CameraCore")
            ],
            path: "Sources/ZoomAdapter",
            resources: [
                .copy("Resources/select_zoom_camera.scpt")
            ]
        ),
        .target(
            name: "TeamsAdapter",
            dependencies: [
                "AppAutomationCore",
                .product(name: "Logging", package: "Logging"),
                .product(name: "CameraCore", package: "CameraCore")
            ],
            path: "Sources/TeamsAdapter",
            resources: [
                .copy("Resources/select_teams_camera.scpt")
            ]
        )
    ]
)
