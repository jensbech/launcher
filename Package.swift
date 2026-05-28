// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Launcher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(
            name: "Launcher",
            dependencies: ["LauncherCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "LauncherCoreTests",
            dependencies: ["LauncherCore"]
        ),
    ]
)
