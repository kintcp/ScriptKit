# ScriptKit

## Android (Gradle)

To use the Android AAR, add the following to your `build.gradle`:

```gradle
repositories {
    maven { url 'https://kintcp.github.io/ScriptKit/' }
}

dependencies {
    implementation 'org.xscript:ScriptKit.QuickJS:1.0.5'
    // or for V8
    implementation 'org.xscript:ScriptKit.V8:1.0.5'
}
```

The V8 AAR is built with Android NDK 29. Consumers should set `ndkVersion "29.0.14206865"` or newer.

## Swift Package Manager (SPM)

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kintcp/ScriptKit.git", from: "1.0.5")
]
```
