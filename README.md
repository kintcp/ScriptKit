# X.Script.QuickJS

## Android (Gradle)

To use the Android AAR, add the following to your `build.gradle`:

```gradle
repositories {
    maven { url 'https://kintcp.github.io/X.Script.QuickJS/' }
}

dependencies {
    implementation 'org.xscript:X.Script.QuickJS:1.0.5'
    // or for V8
    implementation 'org.xscript:X.Script.V8:1.0.5'
}
```

## Swift Package Manager (SPM)

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kintcp/X.Script.QuickJS.git", from: "1.0.5")
]
```
