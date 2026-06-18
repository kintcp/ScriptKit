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
            url: "https://github.com/kintcp/ScriptKit/releases/download/spm-v1.0.10/V8.xcframework.zip",
            checksum: "08694dbdb21e42ecabaca205d732a996416f84099fd26839d25da5e1ad79ea4c"),
        .binaryTarget(
            name: "QuickJS",
            url: "https://github.com/kintcp/ScriptKit/releases/download/quickjs-spm-v1.0.11/QuickJS.xcframework.zip",
            checksum: "477d0bce93d1dedf3fb23839d14e4516a164916ff310f426d4b7edd1cb830fee")
    ]
)
