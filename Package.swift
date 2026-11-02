// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Salter",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SalterCore"),
        .executableTarget(name: "Salter", dependencies: ["SalterCore"]),
        .testTarget(
            name: "SalterCoreTests",
            dependencies: ["SalterCore"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
