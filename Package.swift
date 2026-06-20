// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScriptKit",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "V8",
            targets: ["V8"]),
        .library(
            name: "QuickJS",
            targets: ["QuickJS"]),
    ],
    targets: [
        .binaryTarget(
            name: "V8",
            url: "https://github.com/kintcp/ScriptKit/releases/download/spm-v1.0.11/V8.xcframework.zip",
            checksum: "499191c2d2bf88938410723fca7a9517ff3c15427b66fba6b6a5eca34884bd1f"),
        .binaryTarget(
            name: "QuickJS",
            url: "https://github.com/kintcp/ScriptKit/releases/download/quickjs-spm-v1.0.12/QuickJS.xcframework.zip",
            checksum: "044836fd7367dccdb84509f4ef225715c00a551bba940fb7de124379379a709a")
    ]
)
