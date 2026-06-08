#!/bin/bash

set -euo pipefail

# Configuration
V8_VERSION="${1:-15.1.44}"
V8_REPO="https://chromium.googlesource.com/v8/v8.git"
WORKDIR="$(pwd)/v8-apple-build"
DEPOT_TOOLS="$WORKDIR/depot_tools"
V8_DIR="$WORKDIR/v8"
OUTPUT_DIR="$(pwd)/artifacts/v8-spm"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"

# Install depot_tools
if [ ! -d "$DEPOT_TOOLS" ]; then
    echo "Cloning depot_tools..."
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi
export PATH="$DEPOT_TOOLS:$PATH"

# Fetch V8
cd "$WORKDIR"
if [ ! -d "$V8_DIR" ]; then
    echo "Fetching V8..."
    fetch v8
fi

cd "$V8_DIR"
git fetch origin --tags
git checkout "$V8_VERSION"
gclient sync -D

# Build function
build_v8() {
    local platform=$1
    local arch=$2
    local jit_enabled=$3
    local target_name="v8_monolith"
    
    local build_dir="out/${platform}.${arch}.release"
    
    local jit_flag="v8_jitless=true"
    if [ "$jit_enabled" = "true" ]; then
        jit_flag="v8_jitless=false"
    fi
    
    local gn_args="is_debug=false \
        is_component_build=false \
        v8_monolithic=true \
        v8_use_external_startup_data=false \
        v8_enable_i18n_support=false \
        v8_enable_sandbox=false \
        treat_warnings_as_errors=false \
        symbol_level=0 \
        use_custom_libcxx=false \
        use_allocator_shim=false \
        use_partition_alloc_as_malloc=false \
        enable_ios_bitcode=false \
        $jit_flag"
        
    case $platform in
        macos)
            gn_args="$gn_args target_os=\"mac\" target_cpu=\"$arch\""
            ;;
        ios)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" target_environment=\"device\" ios_deployment_target=\"13.0\""
            ;;
        ios-simulator)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" use_remoteexec=false target_environment=\"simulator\""
            ;;
        tvos)
            # Experimental tvOS support using iOS target
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" target_environment=\"device\" ios_deployment_target=\"13.0\""
            ;;
    esac

    echo "Building V8 for $platform $arch (JIT: $jit_enabled)..."
    gn gen "$build_dir" --args="$gn_args"
    ninja -C "$build_dir" "$target_name"
}

# Platforms to build
# macOS: x64, arm64 (JIT: true)
build_v8 macos x64 true
build_v8 macos arm64 true

# iOS: arm64 (JIT: false)
build_v8 ios arm64 false

# iOS Simulator: x64, arm64 (JIT: false)
build_v8 ios-simulator x64 false
build_v8 ios-simulator arm64 false

# Create fat binaries and XCFramework
echo "Creating fat binaries and XCFramework..."

mkdir -p "$OUTPUT_DIR/libs/macos"
mkdir -p "$OUTPUT_DIR/libs/ios"
mkdir -p "$OUTPUT_DIR/libs/ios-simulator"

# macOS Fat
lipo -create \
    "out/macos.x64.release/obj/v8_monolith.a" \
    "out/macos.arm64.release/obj/v8_monolith.a" \
    -output "$OUTPUT_DIR/libs/macos/v8_monolith.a"

# iOS (arm64 only)
cp "out/ios.arm64.release/obj/v8_monolith.a" "$OUTPUT_DIR/libs/ios/v8_monolith.a"

# iOS Simulator Fat
lipo -create \
    "out/ios-simulator.x64.release/obj/v8_monolith.a" \
    "out/ios-simulator.arm64.release/obj/v8_monolith.a" \
    -output "$OUTPUT_DIR/libs/ios-simulator/v8_monolith.a"

# Prepare Headers
mkdir -p "$OUTPUT_DIR/include"
cp -R include/* "$OUTPUT_DIR/include/"

# Create XCFramework
rm -rf "$OUTPUT_DIR/XScriptV8.xcframework"
xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/libs/macos/v8_monolith.a" \
    -headers "$OUTPUT_DIR/include" \
    -library "$OUTPUT_DIR/libs/ios/v8_monolith.a" \
    -headers "$OUTPUT_DIR/include" \
    -library "$OUTPUT_DIR/libs/ios-simulator/v8_monolith.a" \
    -headers "$OUTPUT_DIR/include" \
    -output "$OUTPUT_DIR/XScriptV8.xcframework"

echo "XCFramework created at $OUTPUT_DIR/XScriptV8.xcframework"

cd "$OUTPUT_DIR"
zip -r XScriptV8.xcframework.zip XScriptV8.xcframework
echo "Zipped XCFramework to $OUTPUT_DIR/XScriptV8.xcframework.zip"
