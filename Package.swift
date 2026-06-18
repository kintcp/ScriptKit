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
            url: "https://github.com/kintcp/ScriptKit/releases/download/spm-v1.0.9/V8.xcframework.zip",
            checksum: "6713ae26e3cc81445c71400b214af6a315bb967774c11a5c541c59ef8ed7d404"),
        .binaryTarget(
            name: "QuickJS",
            url: "https://github.com/kintcp/ScriptKit/releases/download/quickjs-spm-v1.0.5/QuickJS.xcframework.zip",
            checksum: "37d667d6b37a616a15377dd90957f7f30ce550cc1087a851b16bc11327e82f00"
        )
    ]
)
