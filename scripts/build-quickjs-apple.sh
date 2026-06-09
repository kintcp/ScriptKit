#!/bin/bash

set -euo pipefail

# Configuration
QUICKJS_VERSION="${1:-master}"
PLATFORM="${2:-}"
ARCH="${3:-}"

QUICKJS_REPO="https://github.com/bellard/quickjs.git"
WORKDIR="$(pwd)/quickjs-apple-build"
QUICKJS_DIR="$WORKDIR/quickjs"
OUTPUT_DIR="$(pwd)/artifacts/quickjs-spm"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"

# Fetch QuickJS
if [ ! -d "$QUICKJS_DIR" ]; then
    echo "Cloning QuickJS..."
    git clone "$QUICKJS_REPO" "$QUICKJS_DIR"
fi

cd "$QUICKJS_DIR"
git fetch origin
git checkout "$QUICKJS_VERSION"

# Patch QuickJS for Apple restricted platforms (tvOS, visionOS, iOS)
# Prohibited functions: execve, system, fork, etc.
echo "Patching quickjs-libc.c for Apple restricted platforms..."
# Use perl for more robust regex handling than sed
perl -pi -e 's/return\s+execve\s*\(.*?\);/return -1;/g' quickjs-libc.c
perl -pi -e 's/\bexecve\s*\(.*?\);/-1;/g' quickjs-libc.c
perl -pi -e 's/\bsystem\s*\(.*?\)/(-1)/g' quickjs-libc.c
perl -pi -e 's/\bfork\s*\(\)/(-1)/g' quickjs-libc.c
perl -pi -e 's/\bwaitpid\s*\(.*?\)/(-1)/g' quickjs-libc.c

# Build function
build_quickjs() {
    local platform=$1
    local arch=$2
    
    local build_dir="$WORKDIR/out/${platform}.${arch}"
    mkdir -p "$build_dir"
    
    local sdk=""
    local target=""
    local min_os=""
    
    case $platform in
        macos)
            sdk="macosx"
            min_os="10.15"
            target="$arch-apple-macosx$min_os"
            ;;
        ios)
            sdk="iphoneos"
            min_os="13.0"
            target="$arch-apple-ios$min_os"
            ;;
        ios-simulator)
            sdk="iphonesimulator"
            min_os="13.0"
            target="$arch-apple-ios$min_os-simulator"
            ;;
        tvos)
            sdk="appletvos"
            min_os="13.0"
            target="$arch-apple-tvos$min_os"
            ;;
        tvos-simulator)
            sdk="appletvsimulator"
            min_os="13.0"
            target="$arch-apple-tvos$min_os-simulator"
            ;;
        visionos)
            sdk="xros"
            min_os="1.0"
            target="$arch-apple-xros$min_os"
            ;;
        visionos-simulator)
            sdk="xrsimulator"
            min_os="1.0"
            target="$arch-apple-xros$min_os-simulator"
            ;;
    esac

    local sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    local cc="clang"
    local ar="ar"
    
    local cflags="-O3 -D_GNU_SOURCE -D_DARWIN_C_SOURCE -DCONFIG_VERSION=\"$(cat VERSION)\" -DCONFIG_BIGNUM -target $target -isysroot $sdk_path -fembed-bitcode-marker"
    
    echo "Building QuickJS for $platform $arch ($target)..."
    
    # List of source files to compile
    local sources=(
        "quickjs.c"
        "libregexp.c"
        "libunicode.c"
        "cutils.c"
        "quickjs-libc.c"
        "libbf.c"
    )

    # Check for optional but recommended files
    if [ -f "qjscalc.c" ]; then
        sources+=("qjscalc.c")
    fi
    
    local objects=()
    for src in "${sources[@]}"; do
        if [ -f "$src" ]; then
            local obj="$build_dir/${src%.c}.o"
            $cc $cflags -I. -c "$src" -o "$obj"
            objects+=("$obj")
        fi
    done
    
    local lib_out="$build_dir/libquickjs.a"
    $ar rcs "$lib_out" "${objects[@]}"

    # Copy output to artifacts
    mkdir -p "$OUTPUT_DIR/libs/$platform/$arch"
    cp "$lib_out" "$OUTPUT_DIR/libs/$platform/$arch/libquickjs.a"
}

if [ -n "$PLATFORM" ] && [ -n "$ARCH" ] && [ "$PLATFORM" != "bundle" ]; then
    build_quickjs "$PLATFORM" "$ARCH"
    
    # Export headers
    if [ "$PLATFORM" = "macos" ] && [ "$ARCH" = "arm64" ]; then
        echo "Exporting headers..."
        mkdir -p "$OUTPUT_DIR/include"
        cp quickjs.h "$OUTPUT_DIR/include/"
        cp quickjs-libc.h "$OUTPUT_DIR/include/"
    fi
    exit 0
fi

if [ "$PLATFORM" = "bundle" ]; then
    echo "Creating fat binaries and XCFramework..."

    mkdir -p "$OUTPUT_DIR/libs-final/macos"
    mkdir -p "$OUTPUT_DIR/libs-final/ios"
    mkdir -p "$OUTPUT_DIR/libs-final/ios-simulator"
    mkdir -p "$OUTPUT_DIR/libs-final/tvos"
    mkdir -p "$OUTPUT_DIR/libs-final/tvos-simulator"
    mkdir -p "$OUTPUT_DIR/libs-final/visionos"
    mkdir -p "$OUTPUT_DIR/libs-final/visionos-simulator"

    # macOS Fat
    lipo -create \
        "$OUTPUT_DIR/libs/macos/x86_64/libquickjs.a" \
        "$OUTPUT_DIR/libs/macos/arm64/libquickjs.a" \
        -output "$OUTPUT_DIR/libs-final/macos/libquickjs.a"

    # iOS
    cp "$OUTPUT_DIR/libs/ios/arm64/libquickjs.a" "$OUTPUT_DIR/libs-final/ios/libquickjs.a"

    # iOS Simulator Fat
    lipo -create \
        "$OUTPUT_DIR/libs/ios-simulator/x86_64/libquickjs.a" \
        "$OUTPUT_DIR/libs/ios-simulator/arm64/libquickjs.a" \
        -output "$OUTPUT_DIR/libs-final/ios-simulator/libquickjs.a"

    # tvOS
    cp "$OUTPUT_DIR/libs/tvos/arm64/libquickjs.a" "$OUTPUT_DIR/libs-final/tvos/libquickjs.a"

    # tvOS Simulator Fat
    lipo -create \
        "$OUTPUT_DIR/libs/tvos-simulator/x86_64/libquickjs.a" \
        "$OUTPUT_DIR/libs/tvos-simulator/arm64/libquickjs.a" \
        -output "$OUTPUT_DIR/libs-final/tvos-simulator/libquickjs.a"

    # visionOS
    cp "$OUTPUT_DIR/libs/visionos/arm64/libquickjs.a" "$OUTPUT_DIR/libs-final/visionos/libquickjs.a"

    # visionOS Simulator
    cp "$OUTPUT_DIR/libs/visionos-simulator/arm64/libquickjs.a" "$OUTPUT_DIR/libs-final/visionos-simulator/libquickjs.a"

    # Headers
    if [ ! -d "$OUTPUT_DIR/include" ]; then
         mkdir -p "$OUTPUT_DIR/include"
         cp quickjs.h "$OUTPUT_DIR/include/"
         cp quickjs-libc.h "$OUTPUT_DIR/include/"
    fi

    # Create XCFramework
    rm -rf "$OUTPUT_DIR/X.Script.QuickJS.xcframework"
    xcodebuild -create-xcframework \
        -library "$OUTPUT_DIR/libs-final/macos/libquickjs.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/ios/libquickjs.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/ios-simulator/libquickjs.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/tvos/libquickjs.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/tvos-simulator/libquickjs.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/visionos/libquickjs.a" \
        -headers "$OUTPUT_DIR/include" \
        -library "$OUTPUT_DIR/libs-final/visionos-simulator/libquickjs.a" \
        -headers "$OUTPUT_DIR/include" \
        -output "$OUTPUT_DIR/X.Script.QuickJS.xcframework"

    echo "XCFramework created at $OUTPUT_DIR/X.Script.QuickJS.xcframework"

    cd "$OUTPUT_DIR"
    zip -q -r X.Script.QuickJS.xcframework.zip X.Script.QuickJS.xcframework
    exit 0
fi

# Default sequential build
platforms=("macos" "macos" "ios" "ios-simulator" "ios-simulator" "tvos" "tvos-simulator" "tvos-simulator" "visionos" "visionos-simulator")
archs=("x86_64" "arm64" "arm64" "x86_64" "arm64" "arm64" "x86_64" "arm64" "arm64" "arm64")

for i in "${!platforms[@]}"; do
    build_quickjs "${platforms[$i]}" "${archs[$i]}"
done

$0 "$QUICKJS_VERSION" bundle
