#!/bin/bash

set -euo pipefail

# Configuration
V8_VERSION="${1:-15.1.44}"
TARGET_CPU="${2:-}"
ANDROID_ABI="${3:-}"

V8_REPO="https://chromium.googlesource.com/v8/v8.git"
WORKDIR="$(pwd)/v8-android-build"
DEPOT_TOOLS="$WORKDIR/depot_tools"
V8_DIR="$WORKDIR/v8"
OUTPUT_DIR="$(pwd)/artifacts/v8-android"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"

# Install depot_tools
if [ ! -d "$DEPOT_TOOLS" ]; then
    echo "Cloning depot_tools..."
    git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi
export PATH="$DEPOT_TOOLS:$PATH"

# Fetch V8 and setup Android target
cd "$WORKDIR"
if [ ! -d "$V8_DIR" ]; then
    echo "Fetching V8..."
    fetch --nohooks v8
    echo "target_os = ['android']" >> .gclient
fi

cd "$V8_DIR"
git fetch origin --tags
git checkout "$V8_VERSION"

echo "Running gclient sync..."
gclient sync -D --no-history --shallow

# Install build dependencies on Linux
if [ "$(uname)" = "Linux" ] && [ -f "build/install-build-deps.sh" ]; then
    echo "Installing build dependencies..."
    sudo ./build/install-build-deps.sh --android --no-prompt || echo "Failed to install some deps, continuing anyway"
fi

patch_v8_android_build_config() {
    local ndk_root="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
    if [ -z "$ndk_root" ]; then
        return
    fi

    if [ ! -d "$ndk_root/toolchains/llvm/prebuilt" ]; then
        echo "ANDROID_NDK_HOME/ANDROID_NDK_ROOT does not look like an Android NDK: $ndk_root" >&2
        return 1
    fi

    echo "Using Android NDK: $ndk_root"
    python3 - "$ndk_root" <<'PY'
from pathlib import Path
import sys

ndk_root = sys.argv[1]
path = Path("build/config/android/config.gni")
text = path.read_text()
old = '  android_ndk_root = "//third_party/android_toolchain/ndk"'
new = f'  android_ndk_root = "{ndk_root}"'
if old not in text and new not in text:
    raise SystemExit("Unable to patch android_ndk_root in build/config/android/config.gni")
path.write_text(text.replace(old, new, 1))
PY
}

verify_no_missing_libcxx_hash_memory() {
    local archive=$1
    if nm -u "$archive" | grep -q "_ZNSt6__ndk113__hash_memory"; then
        echo "libv8.a exposes unresolved std::__ndk1::__hash_memory; rebuild with a compatible Android NDK/libc++" >&2
        return 1
    fi
}

patch_v8_android_build_config

# Build function
build_v8() {
    local target_cpu=$1
    local android_abi=$2
    local target_name="v8_monolith"
    
    local build_dir="out/android.${target_cpu}.release"
    
    local gn_args="target_os=\"android\" \
        target_cpu=\"$target_cpu\" \
        is_debug=false \
        is_component_build=false \
        v8_monolithic=true \
        v8_use_external_startup_data=false \
        v8_enable_i18n_support=true \
        v8_enable_temporal_support=false \
        enable_rust=false \
        v8_enable_sandbox=false \
        v8_generate_external_defines_header=true \
        treat_warnings_as_errors=false \
        symbol_level=0 \
        use_custom_libcxx=false \
        use_allocator_shim=false \
        use_partition_alloc_as_malloc=false"
        
    echo "Building V8 for Android $target_cpu ($android_abi)..."
    gn gen "$build_dir" --args="$gn_args"
    ninja -C "$build_dir" "$target_name"

    # Copy output to artifacts
    mkdir -p "$OUTPUT_DIR/libs/$android_abi"
    cp "$build_dir/obj/libv8_monolith.a" "$OUTPUT_DIR/libs/$android_abi/libv8.a"
    verify_no_missing_libcxx_hash_memory "$OUTPUT_DIR/libs/$android_abi/libv8.a"

    # Copy v8-gn.h
    mkdir -p "$OUTPUT_DIR/abi_includes/$android_abi"
    if [ -f "$build_dir/gen/include/v8-gn.h" ]; then
        cp "$build_dir/gen/include/v8-gn.h" "$OUTPUT_DIR/abi_includes/$android_abi/v8-gn.h"
    fi
    
    # Copy ICU libraries if they exist separately (sometimes they are not merged into monolith)
    # Search in multiple possible locations
    find "$build_dir/obj/third_party/icu" -name "*.a" -exec cp {} "$OUTPUT_DIR/libs/$android_abi/" \; || echo "No extra ICU libs found in obj/third_party/icu"
}

if [ -n "$TARGET_CPU" ] && [ -n "$ANDROID_ABI" ]; then
    # Build single architecture
    build_v8 "$TARGET_CPU" "$ANDROID_ABI"
    
    # If this is the bundling run or we want to export headers
    if [ "$TARGET_CPU" = "arm64" ]; then
        echo "Exporting headers..."
        mkdir -p "$OUTPUT_DIR/include"
        cp -R include/* "$OUTPUT_DIR/include/"
    fi
    exit 0
fi

if [ "$TARGET_CPU" = "bundle" ]; then
    # Create AAR with Prefab
    echo "Creating Android AAR with Prefab..."
    AAR_DIR="$OUTPUT_DIR/aar_contents"
    rm -rf "$AAR_DIR"
    mkdir -p "$AAR_DIR"

    # AAR Root files
    cat > "$AAR_DIR/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="org.xscript.v8"
    android:versionCode="1"
    android:versionName="$V8_VERSION" >
    <uses-sdk android:minSdkVersion="21" android:targetSdkVersion="34" />
</manifest>
EOF

    touch "$AAR_DIR/R.txt"

    mkdir -p "$AAR_DIR/META-INF"
    cat > "$AAR_DIR/META-INF/MANIFEST.MF" <<EOF
Manifest-Version: 1.0
Created-By: 1.0 (Android)
EOF
    (cd "$AAR_DIR" && zip -q -r classes.jar META-INF && rm -rf META-INF)

    # Prefab configuration
    PREFAB_DIR="$AAR_DIR/prefab"
    mkdir -p "$PREFAB_DIR/modules/v8/include"
    
    # In bundle mode, headers should be in $OUTPUT_DIR/include
    if [ -d "$OUTPUT_DIR/include" ]; then
        cp -R "$OUTPUT_DIR/include/"* "$PREFAB_DIR/modules/v8/include/"
    elif [ -d "include" ]; then
         cp -R include/* "$PREFAB_DIR/modules/v8/include/"
    fi

    cat > "$PREFAB_DIR/prefab.json" <<EOF
{
  "schema_version": 2,
  "name": "v8",
  "version": "$V8_VERSION",
  "dependencies": []
}
EOF

    cat > "$PREFAB_DIR/modules/v8/module.json" <<EOF
{
  "export_libraries": []
}
EOF

    # Patch v8config.h in the AAR to unconditionally include v8-gn.h
    # This avoids the need for users to define V8_GN_HEADER manually.
    find "$PREFAB_DIR/modules/v8/include" -name "v8config.h" -exec sed -i 's/#ifdef V8_GN_HEADER/#if 1 \/\/ V8_GN_HEADER patched/g' {} +


    pack_prefab_abi() {
        local android_abi=$1
        local abi_dir="$PREFAB_DIR/modules/v8/libs/android.$android_abi"
        
        mkdir -p "$abi_dir/include"
        
        # Copy ABI-specific v8-gn.h
        if [ -f "$OUTPUT_DIR/abi_includes/$android_abi/v8-gn.h" ]; then
            cp "$OUTPUT_DIR/abi_includes/$android_abi/v8-gn.h" "$abi_dir/include/v8-gn.h"
        fi

        # Copy all static libraries found for this ABI. The module library itself
        # is linked by Prefab; export_libraries must only list extra libraries.
        for lib_path in "$OUTPUT_DIR/libs/$android_abi/"*.a; do
            if [ -f "$lib_path" ]; then
                local lib_name=$(basename "$lib_path")
                cp "$lib_path" "$abi_dir/$lib_name"
            fi
        done
        
        cat > "$abi_dir/abi.json" <<EOF
{
  "abi": "$android_abi",
  "api": 21,
  "ndk": 29,
  "stl": "c++_shared"
}
EOF
    }

    pack_prefab_abi armeabi-v7a
    pack_prefab_abi arm64-v8a
    pack_prefab_abi x86
    pack_prefab_abi x86_64

    # Zip it all up
    cd "$AAR_DIR"
    zip -q -r "$OUTPUT_DIR/X.Script.V8.aar" .
    echo "AAR successfully created at $OUTPUT_DIR/X.Script.V8.aar"
    exit 0
fi

# Platforms to build sequentially if no arguments provided
build_v8 arm armeabi-v7a
build_v8 arm64 arm64-v8a
build_v8 x86 x86
build_v8 x64 x86_64

# Export headers for sequential build
echo "Exporting headers..."
mkdir -p "$OUTPUT_DIR/include"
cp -R include/* "$OUTPUT_DIR/include/"

# Perform bundling
$0 "$V8_VERSION" bundle
