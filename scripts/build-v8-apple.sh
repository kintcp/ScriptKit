#!/bin/bash

set -euo pipefail

# Configuration
V8_VERSION="${1:-15.1.44}"
PLATFORM="${2:-}"
ARCH="${3:-}"
JIT_ENABLED="${4:-false}"

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
    git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi
export PATH="$DEPOT_TOOLS:$PATH"

# Fetch V8
cd "$WORKDIR"
if [ ! -d "$V8_DIR" ]; then
    echo "Fetching V8..."
    fetch --nohooks v8
    echo "target_os = ['ios', 'mac']" >> .gclient
fi

cd "$V8_DIR"
git fetch origin --tags
git checkout "$V8_VERSION"

echo "Running gclient sync..."
gclient sync -D --no-history --shallow

# Build function
build_v8() {
    local platform=$1
    local arch=$2
    local jit_enabled=$3
    local target_name="v8_monolith"
    
    local build_dir="out/${platform}.${arch}.release"
    
    local jit_flag="v8_jitless=true v8_enable_sparkplug=false v8_enable_maglev=false v8_enable_turbofan=false v8_enable_webassembly=false"
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
        use_remoteexec=false \
        enable_ios_bitcode=false \
        ios_enable_code_signing=false \
        ios_code_signing_identity=\"\" \
        $jit_flag"
        
    case $platform in
        macos)
            gn_args="$gn_args target_os=\"mac\" target_cpu=\"$arch\""
            ;;
        ios)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" target_environment=\"device\" ios_deployment_target=\"13.0\""
            ;;
        ios-simulator)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" target_environment=\"simulator\" ios_deployment_target=\"13.0\""
            ;;
        tvos)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" ios_sdk_name=\"appletvos\" ios_deployment_target=\"13.0\""
            ;;
        tvos-simulator)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" ios_sdk_name=\"appletvsimulator\" ios_deployment_target=\"13.0\""
            ;;
        visionos)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" ios_sdk_name=\"xros\" ios_deployment_target=\"1.0\""
            ;;
        visionos-simulator)
            gn_args="$gn_args target_os=\"ios\" target_cpu=\"$arch\" ios_sdk_name=\"xrsimulator\" ios_deployment_target=\"1.0\""
            ;;
    esac

    echo "Building V8 for $platform $arch (JIT: $jit_enabled)..."
    gn gen "$build_dir" --args="$gn_args"
    ninja -C "$build_dir" "$target_name"

    # Copy output to artifacts
    mkdir -p "$OUTPUT_DIR/libs/$platform/$arch"
    cp "$build_dir/obj/libv8_monolith.a" "$OUTPUT_DIR/libs/$platform/$arch/v8_monolith.a"
}

if [ -n "$PLATFORM" ] && [ -n "$ARCH" ] && [ "$PLATFORM" != "bundle" ]; then
    # Build single platform/architecture
    build_v8 "$PLATFORM" "$ARCH" "$JIT_ENABLED"
    
    # Export headers if requested or for first arch
    if [ "$PLATFORM" = "macos" ] && [ "$ARCH" = "arm64" ]; then
        echo "Exporting headers..."
        mkdir -p "$OUTPUT_DIR/include"
        cp -R include/* "$OUTPUT_DIR/include/"
    fi
    exit 0
fi

if [ "$PLATFORM" = "bundle" ]; then
    # Create fat binaries and XCFramework
    echo "Creating fat binaries and XCFramework from pre-built libraries..."

    mkdir -p "$OUTPUT_DIR/libs-final/macos"
    mkdir -p "$OUTPUT_DIR/libs-final/ios"
    mkdir -p "$OUTPUT_DIR/libs-final/ios-simulator"
    mkdir -p "$OUTPUT_DIR/libs-final/tvos"
    mkdir -p "$OUTPUT_DIR/libs-final/tvos-simulator"
    mkdir -p "$OUTPUT_DIR/libs-final/visionos"
    mkdir -p "$OUTPUT_DIR/libs-final/visionos-simulator"

    # macOS Fat
    lipo -create \
        "$OUTPUT_DIR/libs/macos/x64/v8_monolith.a" \
        "$OUTPUT_DIR/libs/macos/arm64/v8_monolith.a" \
        -output "$OUTPUT_DIR/libs-final/macos/v8_monolith.a"

    # iOS (arm64 only)
    cp "$OUTPUT_DIR/libs/ios/arm64/v8_monolith.a" "$OUTPUT_DIR/libs-final/ios/v8_monolith.a"

    # iOS Simulator Fat
    lipo -create \
        "$OUTPUT_DIR/libs/ios-simulator/x64/v8_monolith.a" \
        "$OUTPUT_DIR/libs/ios-simulator/arm64/v8_monolith.a" \
        -output "$OUTPUT_DIR/libs-final/ios-simulator/v8_monolith.a"

    # tvOS (arm64 only)
    cp "$OUTPUT_DIR/libs/tvos/arm64/v8_monolith.a" "$OUTPUT_DIR/libs-final/tvos/v8_monolith.a"

    # tvOS Simulator Fat
    lipo -create \
        "$OUTPUT_DIR/libs/tvos-simulator/x64/v8_monolith.a" \
        "$OUTPUT_DIR/libs/tvos-simulator/arm64/v8_monolith.a" \
        -output "$OUTPUT_DIR/libs-final/tvos-simulator/v8_monolith.a"

    # visionOS (arm64 only)
    cp "$OUTPUT_DIR/libs/visionos/arm64/v8_monolith.a" "$OUTPUT_DIR/libs-final/visionos/v8_monolith.a"

    # visionOS Simulator (arm64 only)
    cp "$OUTPUT_DIR/libs/visionos-simulator/arm64/v8_monolith.a" "$OUTPUT_DIR/libs-final/visionos-simulator/v8_monolith.a"

    # Headers should already be in $OUTPUT_DIR/include
    if [ ! -d "$OUTPUT_DIR/include" ]; then
         echo "Exporting headers..."
         mkdir -p "$OUTPUT_DIR/include"
         cp -R include/* "$OUTPUT_DIR/include/"
    fi

    # Create XCFramework
    rm -rf "$OUTPUT_DIR/XScriptV8.xcframework"
    xcodebuild -create-xcframework \
        -library "$OUTPUT_DIR/libs-final/macos/v8_monolith.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/ios/v8_monolith.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/ios-simulator/v8_monolith.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/tvos/v8_monolith.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/tvos-simulator/v8_monolith.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/visionos/v8_monolith.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/visionos-simulator/v8_monolith.a" \
        -headers "$OUTPUT_DIR/include" \
        -output "$OUTPUT_DIR/XScriptV8.xcframework"

    echo "XCFramework created at $OUTPUT_DIR/XScriptV8.xcframework"

    cd "$OUTPUT_DIR"
    zip -q -r XScriptV8.xcframework.zip XScriptV8.xcframework
    echo "Zipped XCFramework to $OUTPUT_DIR/XScriptV8.xcframework.zip"
    exit 0
fi

# Sequential fallback
build_v8 macos x64 true
build_v8 macos arm64 true
build_v8 ios arm64 false
build_v8 ios-simulator x64 false
build_v8 ios-simulator arm64 false

$0 "$V8_VERSION" bundle
