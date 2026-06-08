#!/bin/bash

set -euo pipefail

# Configuration
VERSION="${1:-master}"
QUICKJS_REPO="https://github.com/bellard/quickjs.git"

WORKDIR="$(pwd)/quickjs-android-build"
QUICKJS_DIR="$WORKDIR/quickjs"
OUTPUT_DIR="$(pwd)/artifacts/quickjs-android"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    if [ -d "$ANDROID_SDK_ROOT/ndk" ]; then
        LATEST_NDK=$(ls -d "$ANDROID_SDK_ROOT/ndk"/* | tail -n 1)
        export ANDROID_NDK_HOME="$LATEST_NDK"
    else
        echo "Error: ANDROID_NDK_HOME is not set."
        exit 1
    fi
fi
echo "Using NDK: $ANDROID_NDK_HOME"

HOST_TAG="linux-x86_64"
if [ "$(uname)" = "Darwin" ]; then
    HOST_TAG="darwin-x86_64"
fi
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
MIN_SDK="21"

# Fetch QuickJS
cd "$WORKDIR"
if [ ! -d "$QUICKJS_DIR" ]; then
    echo "Cloning QuickJS..."
    git clone "$QUICKJS_REPO" "$QUICKJS_DIR"
fi

cd "$QUICKJS_DIR"
git fetch origin
git checkout "$VERSION"
QUICKJS_COMMIT="$(git rev-parse HEAD)"
echo "Building QuickJS commit: $QUICKJS_COMMIT"

build_quickjs() {
    local arch=$1
    local android_abi=$2
    local target=$3
    
    local build_dir="out/android.${android_abi}.release"
    mkdir -p "$build_dir"
    
    local CC="$TOOLCHAIN/bin/${target}${MIN_SDK}-clang"
    local AR="$TOOLCHAIN/bin/llvm-ar"
    
    local cflags=(
        -O2
        -DNDEBUG
        -D_GNU_SOURCE
        -DCONFIG_BIGNUM
        -fPIC
        -fvisibility=hidden
        -Wall
        -Wextra
        -Wno-sign-compare
        -Wno-missing-field-initializers
        -Wno-implicit-fallthrough
        -Wno-unused-parameter
    )
    
    local sources=(
        quickjs.c
        libregexp.c
        libunicode.c
        cutils.c
        libbf.c
    )
    
    local objects=()
    echo "Compiling QuickJS for Android $android_abi..."
    
    for source in "${sources[@]}"; do
        if [ -f "$source" ]; then
            local obj="$build_dir/${source%.c}.o"
            "$CC" "${cflags[@]}" -c "$source" -o "$obj"
            objects+=("$obj")
        fi
    done
    
    # dtoa.c is optional, some older quickjs version don't have libbf.c/dtoa.c logic identical, but we compile what exists.
    if [ -f "dtoa.c" ]; then
        local obj="$build_dir/dtoa.o"
        "$CC" "${cflags[@]}" -c "dtoa.c" -o "$obj"
        objects+=("$obj")
    fi
    
    local lib_out="$build_dir/libquickjs.a"
    "$AR" rcs "$lib_out" "${objects[@]}"
}

build_quickjs arm armeabi-v7a armv7a-linux-androideabi
build_quickjs arm64 arm64-v8a aarch64-linux-android
build_quickjs x86 x86 i686-linux-android
build_quickjs x64 x86_64 x86_64-linux-android

# Create AAR with Prefab
echo "Creating Android AAR with Prefab..."
AAR_DIR="$OUTPUT_DIR/aar_contents"
rm -rf "$AAR_DIR"
mkdir -p "$AAR_DIR"

# AAR Root files
cat > "$AAR_DIR/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="org.xscript.quickjs"
    android:versionCode="1"
    android:versionName="$VERSION" >
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
mkdir -p "$PREFAB_DIR/modules/quickjs/include"

# Copy headers
for header in quickjs.h quickjs-libc.h quickjs-atom.h cutils.h libregexp.h libunicode.h list.h libbf.h; do
    if [ -f "$header" ]; then
        cp "$header" "$PREFAB_DIR/modules/quickjs/include/"
    fi
done

cat > "$PREFAB_DIR/prefab.json" <<EOF
{
  "schema_version": 2,
  "name": "quickjs",
  "version": "1.0.0",
  "dependencies": []
}
EOF

cat > "$PREFAB_DIR/modules/quickjs/module.json" <<EOF
{
  "export_libraries": []
}
EOF

pack_prefab_abi() {
    local android_abi=$1
    local abi_dir="$PREFAB_DIR/modules/quickjs/libs/android.$android_abi"
    
    mkdir -p "$abi_dir"
    cp "out/android.${android_abi}.release/libquickjs.a" "$abi_dir/libquickjs.a"
    
    cat > "$abi_dir/abi.json" <<EOF
{
  "abi": "$android_abi",
  "api": 21,
  "ndk": 25,
  "stl": "none"
}
EOF
}

pack_prefab_abi armeabi-v7a
pack_prefab_abi arm64-v8a
pack_prefab_abi x86
pack_prefab_abi x86_64

# Zip it all up
cd "$AAR_DIR"
zip -q -r "$OUTPUT_DIR/XScriptQuickJS.aar" .
echo "AAR successfully created at $OUTPUT_DIR/XScriptQuickJS.aar"
