# X.Script

## Android (Gradle)

To use the Android AAR, add the following to your `build.gradle`:

```gradle
repositories {
    maven { url 'https://kintcp.github.io/X.Script/' }
}

dependencies {
    implementation 'org.xscript:X.Script.QuickJS:1.0.5'
    // or for V8
    implementation 'org.xscript:X.Script.V8:1.0.5'
}
```

The V8 AAR is built with Android NDK 27. Consumers should use NDK 27 or newer.

## Swift Package Manager (SPM)

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kintcp/X.Script.git", from: "1.0.5")
]
```
