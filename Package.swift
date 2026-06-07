// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XScriptV8",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13)
    ],
    products: [
        .library(
            name: "XScriptV8",
            targets: ["XScriptV8"]),
    ],
    targets: [
        .binaryTarget(
            name: "XScriptV8",
            path: "XScriptV8.xcframework"
        )
    ]
)
