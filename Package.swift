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
            url: "https://github.com/kintcp/X.Script.QuickJS/releases/download/spm-v1.0.4/X.Script.V8.xcframework.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        ),
        .binaryTarget(
            name: "X.Script.QuickJS",
            url: "https://github.com/kintcp/X.Script.QuickJS/releases/download/quickjs-spm-v1.0.5/X.Script.QuickJS.xcframework.zip",
            checksum: "37d667d6b37a616a15377dd90957f7f30ce550cc1087a851b16bc11327e82f00")
    ]
)
