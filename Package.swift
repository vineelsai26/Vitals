// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VitalsCore", targets: ["VitalsCore"]),
        .executable(name: "VitalsApp", targets: ["VitalsApp"]),
        .executable(name: "vitals-selftest", targets: ["vitals-selftest"]),
    ],
    dependencies: [
        // Shared design system for the vstack macOS apps.
        .package(path: "../vkit"),
    ],
    targets: [
        .target(
            name: "VitalsCore",
            path: "Sources/VitalsCore"
        ),
        .executableTarget(
            name: "VitalsApp",
            dependencies: [
                "VitalsCore",
                .product(name: "VKit", package: "vkit"),
            ],
            path: "Sources/VitalsApp"
        ),
        .executableTarget(
            name: "vitals-selftest",
            dependencies: ["VitalsCore"],
            path: "Sources/vitals-selftest"
        ),
        .testTarget(
            name: "VitalsCoreTests",
            dependencies: ["VitalsCore"],
            path: "Tests/VitalsCoreTests"
        ),
    ]
)
