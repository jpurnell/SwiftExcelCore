// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftExcelCore",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "SwiftExcelCore", targets: ["SwiftExcelCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3")
    ],
    targets: [
        .target(
            name: "SwiftExcelCore",
            path: "Sources/SwiftExcelCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "SwiftExcelCoreTests",
            dependencies: ["SwiftExcelCore"],
            path: "Tests/SwiftExcelCoreTests"
        )
    ]
)
