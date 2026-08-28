// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IPhoneCamLite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "IPhoneCamLite", targets: ["IPhoneCamLite"])
    ],
    dependencies: [
        .package(name: "Logging", path: "Packages/Logging"),
        .package(name: "SystemChecks", path: "Packages/SystemChecks"),
        .package(name: "CameraCore", path: "Packages/CameraCore"),
        .package(name: "AppAutomation", path: "Packages/AppAutomation")
    ],
    targets: [
        .executableTarget(
            name: "IPhoneCamLite",
            dependencies: [
                .product(name: "Logging", package: "Logging"),
                .product(name: "SystemChecks", package: "SystemChecks"),
                .product(name: "CameraCore", package: "CameraCore"),
                .product(name: "ZoomAdapter", package: "AppAutomation"),
                .product(name: "TeamsAdapter", package: "AppAutomation")
            ],
            path: "App"
        ),
        .testTarget(
            name: "CameraCoreTests",
            dependencies: [
                .product(name: "CameraCore", package: "CameraCore"),
                .product(name: "Logging", package: "Logging")
            ],
            path: "Tests/CameraCoreTests"
        ),
        .testTarget(
            name: "AdapterFixtureTests",
            dependencies: [
                .product(name: "CameraCore", package: "CameraCore"),
                .product(name: "AppAutomationCore", package: "AppAutomation"),
                .product(name: "ZoomAdapter", package: "AppAutomation"),
                .product(name: "TeamsAdapter", package: "AppAutomation")
            ],
            path: "Tests/AdapterFixtureTests"
        ),
        .testTarget(
            name: "UITests",
            dependencies: [
                "IPhoneCamLite",
                .product(name: "CameraCore", package: "CameraCore"),
                .product(name: "SystemChecks", package: "SystemChecks")
            ],
            path: "Tests/UITests"
        )
    ]
)
