// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftJSRuntime",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(name: "SwiftJSRuntime", targets: ["SwiftJSRuntime"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftJSRuntime",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
            ])
    ]
)
