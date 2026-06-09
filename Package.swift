// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "X.Script.V8",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "X.Script.V8",
            targets: ["X.Script.V8"]),
        .library(
            name: "X.Script.QuickJS",
            targets: ["X.Script.QuickJS"]),
    ],
    targets: [
        .binaryTarget(
            name: "X.Script.V8",
            path: "X.Script.V8.xcframework"
        ),
        .binaryTarget(
            name: "X.Script.QuickJS",
            path: "X.Script.QuickJS.xcframework"
        )
    ]
)
