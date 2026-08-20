// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WardrobeKit",
    defaultLocalization: "en",
    // macOS listed only so `swift test` runs on the host without a simulator.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WardrobeKit", targets: ["WardrobeKit"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        // ... your other packages ...
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.4.0")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")]
        ),
        .target(
            name: "WardrobeKit",
            dependencies: [
                "DesignSystem",
                .product(name: "Lottie", package: "lottie-ios")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WardrobeKitTests",
            dependencies: ["WardrobeKit"]
        ),
    ]
    
)
