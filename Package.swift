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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SwiftJSRuntime",
            dependencies: [])
    ]
)
