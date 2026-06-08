#!/bin/bash

set -euo pipefail

# Configuration
V8_VERSION="${1:-15.1.44}"
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
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
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
gclient sync -D

# Install build dependencies on Linux
if [ "$(uname)" = "Linux" ] && [ -f "build/install-build-deps.sh" ]; then
    echo "Installing build dependencies..."
    sudo ./build/install-build-deps.sh --android --no-prompt || echo "Failed to install some deps, continuing anyway"
fi

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
        v8_enable_i18n_support=false \
        v8_enable_sandbox=false \
        treat_warnings_as_errors=false \
        symbol_level=0 \
        use_custom_libcxx=false \
        use_allocator_shim=false \
        use_partition_alloc_as_malloc=false"
        
    echo "Building V8 for Android $target_cpu ($android_abi)..."
    gn gen "$build_dir" --args="$gn_args"
    ninja -C "$build_dir" "$target_name"
}

# Platforms to build
build_v8 arm armeabi-v7a
build_v8 arm64 arm64-v8a
build_v8 x86 x86
build_v8 x64 x86_64

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
cp -R include/* "$PREFAB_DIR/modules/v8/include/"

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

pack_prefab_abi() {
    local target_cpu=$1
    local android_abi=$2
    local abi_dir="$PREFAB_DIR/modules/v8/libs/android.$android_abi"
    
    mkdir -p "$abi_dir"
    cp "out/android.${target_cpu}.release/obj/libv8_monolith.a" "$abi_dir/libv8.a"
    
    cat > "$abi_dir/abi.json" <<EOF
{
  "abi": "$android_abi",
  "api": 21,
  "ndk": 25,
  "stl": "c++_shared"
}
EOF
}

pack_prefab_abi arm armeabi-v7a
pack_prefab_abi arm64 arm64-v8a
pack_prefab_abi x86 x86
pack_prefab_abi x64 x86_64

# Zip it all up
cd "$AAR_DIR"
zip -q -r "$OUTPUT_DIR/XScriptV8.aar" .
echo "AAR successfully created at $OUTPUT_DIR/XScriptV8.aar"
