// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sift",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SiftCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Sift",
            dependencies: ["SiftCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "SiftCoreTests",
            dependencies: ["SiftCore"]
        ),
    ]
)
