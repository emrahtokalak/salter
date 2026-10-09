// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DevLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DevLauncherCore"),
        .executableTarget(name: "DevLauncher", dependencies: ["DevLauncherCore"]),
        .testTarget(
            name: "DevLauncherCoreTests",
            dependencies: ["DevLauncherCore"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
