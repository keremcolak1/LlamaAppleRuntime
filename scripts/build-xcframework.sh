#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/runtime.sh
source "$ROOT/scripts/lib/runtime.sh"

load_runtime_config "$ROOT"

SKIP_BOOTSTRAP=0
DRY_RUN=0
CLEAN=0
CONFIGURATION="${LLAMA_APPLE_CONFIGURATION:-Release}"
PLATFORMS="${LLAMA_APPLE_PLATFORMS}"

BUILD_SHARED_LIBS=OFF
LLAMA_BUILD_EXAMPLES=OFF
LLAMA_BUILD_TOOLS=ON
LLAMA_BUILD_TESTS=OFF
LLAMA_BUILD_SERVER=OFF
GGML_METAL=ON
GGML_METAL_EMBED_LIBRARY=ON
GGML_BLAS_DEFAULT=ON
GGML_METAL_USE_BF16=ON
GGML_OPENMP=OFF

COMMON_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"
COMMON_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -Wno-cast-qual -g"

usage() {
    cat <<'USAGE'
Usage: scripts/build-xcframework.sh [options]

Builds artifacts/LlamaApple.xcframework from the pinned llama.cpp checkout.

Options:
  --skip-bootstrap       Use the existing .build/upstream/llama.cpp checkout.
  --platforms <list>     Comma-separated: ios-device,ios-simulator,macos.
  --configuration <name> Xcode/CMake configuration. Default: Release.
  --clean                Remove previous native build output before building.
  --dry-run              Print the build plan without fetching or compiling.
  --help                 Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-bootstrap)
            SKIP_BOOTSTRAP=1
            shift
            ;;
        --platforms)
            [[ $# -ge 2 ]] || die "--platforms requires a comma-separated value"
            PLATFORMS="$2"
            shift 2
            ;;
        --configuration)
            [[ $# -ge 2 ]] || die "--configuration requires a value"
            CONFIGURATION="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

CHECKOUT_DIR="$(upstream_checkout_dir "$ROOT")"
BUILD_ROOT="$ROOT/.build/native"
ARTIFACTS="$(artifact_dir "$ROOT")"
OUTPUT_XCFRAMEWORK="$ARTIFACTS/$LLAMA_APPLE_FRAMEWORK_NAME.xcframework"

COMMON_CMAKE_ARGS=(
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym
    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES
    -DCMAKE_XCODE_ATTRIBUTE_COPY_PHASE_STRIP=NO
    -DCMAKE_XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT=NO
    -DBUILD_SHARED_LIBS="$BUILD_SHARED_LIBS"
    -DLLAMA_BUILD_EXAMPLES="$LLAMA_BUILD_EXAMPLES"
    -DLLAMA_BUILD_TOOLS="$LLAMA_BUILD_TOOLS"
    -DLLAMA_BUILD_TESTS="$LLAMA_BUILD_TESTS"
    -DLLAMA_BUILD_SERVER="$LLAMA_BUILD_SERVER"
    -DGGML_METAL="$GGML_METAL"
    -DGGML_METAL_EMBED_LIBRARY="$GGML_METAL_EMBED_LIBRARY"
    -DGGML_BLAS_DEFAULT="$GGML_BLAS_DEFAULT"
    -DGGML_METAL_USE_BF16="$GGML_METAL_USE_BF16"
    -DGGML_NATIVE=OFF
    -DGGML_OPENMP="$GGML_OPENMP"
)

print_plan() {
    cat <<MESSAGE
[LlamaAppleRuntime] Build plan

  Output:        $OUTPUT_XCFRAMEWORK
  Upstream:      $LLAMA_CPP_REPOSITORY @ $LLAMA_CPP_REVISION
  Checkout:      $CHECKOUT_DIR
  Configuration: $CONFIGURATION
  Platforms:     $PLATFORMS

  CMake contract:
    -DLLAMA_BUILD_TOOLS=ON
    --target mtmd

  Public headers copied into every framework slice:
    include/llama.h
    ggml/include/ggml.h
    ggml/include/gguf.h
    tools/mtmd/mtmd.h
    tools/mtmd/mtmd-helper.h

  Final packaging command:
    xcodebuild -create-xcframework ... -output $OUTPUT_XCFRAMEWORK
MESSAGE
}

split_platforms() {
    printf '%s\n' "$PLATFORMS" | tr ',' '\n' | sed '/^$/d'
}

platform_build_dir() {
    printf '%s/%s\n' "$BUILD_ROOT" "$1"
}

platform_release_dir() {
    case "$1" in
        ios-device) printf '%s-iphoneos\n' "$CONFIGURATION" ;;
        ios-simulator) printf '%s-iphonesimulator\n' "$CONFIGURATION" ;;
        macos) printf '%s\n' "$CONFIGURATION" ;;
        *) die "unsupported platform: $1" ;;
    esac
}

platform_kind() {
    case "$1" in
        ios-device|ios-simulator) printf 'ios\n' ;;
        macos) printf 'macos\n' ;;
        *) die "unsupported platform: $1" ;;
    esac
}

platform_is_simulator() {
    case "$1" in
        ios-simulator) printf 'true\n' ;;
        ios-device|macos) printf 'false\n' ;;
        *) die "unsupported platform: $1" ;;
    esac
}

framework_binary_path() {
    local build_dir="$1"
    local kind="$2"

    if [[ "$kind" == "macos" ]]; then
        printf '%s/framework/%s.framework/Versions/A/%s\n' "$build_dir" "$LLAMA_APPLE_FRAMEWORK_NAME" "$LLAMA_APPLE_FRAMEWORK_NAME"
    else
        printf '%s/framework/%s.framework/%s\n' "$build_dir" "$LLAMA_APPLE_FRAMEWORK_NAME" "$LLAMA_APPLE_FRAMEWORK_NAME"
    fi
}

require_build_tools() {
    require_command cmake
    require_command xcrun
}

configure_platform() {
    local platform="$1"
    local build_dir
    build_dir="$(platform_build_dir "$platform")"

    local args=(
        -B "$build_dir"
        -G Xcode
        "${COMMON_CMAKE_ARGS[@]}"
        -DCMAKE_C_FLAGS="$COMMON_C_FLAGS"
        -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS"
        -DLLAMA_OPENSSL=OFF
        -S "$CHECKOUT_DIR"
    )

    case "$platform" in
        ios-device)
            args+=(
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN_OS_VERSION"
                -DCMAKE_SYSTEM_NAME=iOS
                -DCMAKE_OSX_SYSROOT=iphoneos
                -DCMAKE_OSX_ARCHITECTURES=arm64
                -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos
            )
            ;;
        ios-simulator)
            args+=(
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN_OS_VERSION"
                -DIOS=ON
                -DCMAKE_SYSTEM_NAME=iOS
                -DCMAKE_OSX_SYSROOT=iphonesimulator
                -DCMAKE_OSX_ARCHITECTURES=arm64\;x86_64
                -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator
            )
            ;;
        macos)
            args+=(
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN_OS_VERSION"
                -DCMAKE_OSX_ARCHITECTURES=arm64\;x86_64
            )
            ;;
        *)
            die "unsupported platform: $platform"
            ;;
    esac

    log "configuring $platform"
    cmake "${args[@]}"
}

build_platform() {
    local platform="$1"
    local build_dir
    build_dir="$(platform_build_dir "$platform")"

    log "building mtmd target for $platform"
    cmake --build "$build_dir" --target mtmd --config "$CONFIGURATION" -- -quiet
}

copy_if_present() {
    local source="$1"
    local destination="$2"

    if [[ -f "$source" ]]; then
        cp "$source" "$destination"
    fi
}

setup_framework_structure() {
    local platform="$1"
    local build_dir
    local kind
    build_dir="$(platform_build_dir "$platform")"
    kind="$(platform_kind "$platform")"

    local framework_dir="$build_dir/framework/$LLAMA_APPLE_FRAMEWORK_NAME.framework"
    local header_path
    local module_path
    local plist_path

    log "creating framework structure for $platform"
    rm -rf "$framework_dir"

    if [[ "$kind" == "macos" ]]; then
        mkdir -p "$framework_dir/Versions/A/Headers" "$framework_dir/Versions/A/Modules" "$framework_dir/Versions/A/Resources"
        ln -sf A "$framework_dir/Versions/Current"
        ln -sf Versions/Current/Headers "$framework_dir/Headers"
        ln -sf Versions/Current/Modules "$framework_dir/Modules"
        ln -sf Versions/Current/Resources "$framework_dir/Resources"
        ln -sf "Versions/Current/$LLAMA_APPLE_FRAMEWORK_NAME" "$framework_dir/$LLAMA_APPLE_FRAMEWORK_NAME"
        header_path="$framework_dir/Versions/A/Headers"
        module_path="$framework_dir/Versions/A/Modules"
        plist_path="$framework_dir/Versions/A/Resources/Info.plist"
    else
        mkdir -p "$framework_dir/Headers" "$framework_dir/Modules"
        header_path="$framework_dir/Headers"
        module_path="$framework_dir/Modules"
        plist_path="$framework_dir/Info.plist"
    fi

    cp "$CHECKOUT_DIR/include/llama.h" "$header_path/"
    cp "$CHECKOUT_DIR/ggml/include/ggml.h" "$header_path/"
    cp "$CHECKOUT_DIR/ggml/include/gguf.h" "$header_path/"
    copy_if_present "$CHECKOUT_DIR/ggml/include/ggml-alloc.h" "$header_path/"
    copy_if_present "$CHECKOUT_DIR/ggml/include/ggml-backend.h" "$header_path/"
    copy_if_present "$CHECKOUT_DIR/ggml/include/ggml-blas.h" "$header_path/"
    copy_if_present "$CHECKOUT_DIR/ggml/include/ggml-cpu.h" "$header_path/"
    copy_if_present "$CHECKOUT_DIR/ggml/include/ggml-metal.h" "$header_path/"
    copy_if_present "$CHECKOUT_DIR/ggml/include/ggml-opt.h" "$header_path/"
    cp "$CHECKOUT_DIR/tools/mtmd/mtmd.h" "$header_path/"
    cp "$CHECKOUT_DIR/tools/mtmd/mtmd-helper.h" "$header_path/"

    cat > "$module_path/module.modulemap" <<EOF
framework module $LLAMA_APPLE_FRAMEWORK_NAME {
    header "llama.h"
    header "ggml.h"
    header "gguf.h"
    header "mtmd.h"
    header "mtmd-helper.h"

    link "c++"
    link framework "Accelerate"
    link framework "Foundation"
    link framework "Metal"

    export *
}
EOF

    write_info_plist "$platform" "$plist_path"
}

write_info_plist() {
    local platform="$1"
    local plist_path="$2"
    local min_os_version="$IOS_MIN_OS_VERSION"
    local platform_name="iphoneos"
    local supported_platform="iPhoneOS"
    local sdk_name="iphoneos${IOS_MIN_OS_VERSION}"
    local device_family='    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>'

    if [[ "$platform" == "macos" ]]; then
        min_os_version="$MACOS_MIN_OS_VERSION"
        platform_name="macosx"
        supported_platform="MacOSX"
        sdk_name="macosx${MACOS_MIN_OS_VERSION}"
        device_family=""
    fi

    cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$LLAMA_APPLE_FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>org.llamaapple.$LLAMA_APPLE_FRAMEWORK_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$LLAMA_APPLE_FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$LLAMA_APPLE_RELEASE_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>$min_os_version</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$supported_platform</string>
    </array>
$device_family
    <key>DTPlatformName</key>
    <string>$platform_name</string>
    <key>DTSDKName</key>
    <string>$sdk_name</string>
</dict>
</plist>
EOF
}

static_library_paths() {
    local build_dir="$1"
    local release_dir="$2"

    printf '%s\n' \
        "$build_dir/src/$release_dir/libllama.a" \
        "$build_dir/ggml/src/$release_dir/libggml.a" \
        "$build_dir/ggml/src/$release_dir/libggml-base.a" \
        "$build_dir/ggml/src/$release_dir/libggml-cpu.a" \
        "$build_dir/ggml/src/ggml-metal/$release_dir/libggml-metal.a" \
        "$build_dir/ggml/src/ggml-blas/$release_dir/libggml-blas.a" \
        "$build_dir/tools/mtmd/$release_dir/libmtmd.a"
}

combine_static_libraries() {
    local platform="$1"
    local build_dir
    local release_dir
    local kind
    local is_simulator
    build_dir="$(platform_build_dir "$platform")"
    release_dir="$(platform_release_dir "$platform")"
    kind="$(platform_kind "$platform")"
    is_simulator="$(platform_is_simulator "$platform")"

    local binary_path
    binary_path="$(framework_binary_path "$build_dir" "$kind")"

    local temp_dir="$build_dir/temp"
    local combined_lib="$temp_dir/combined.a"
    mkdir -p "$temp_dir"

    local libs=()
    local lib
    while IFS= read -r lib; do
        [[ -f "$lib" ]] || die "missing static library for $platform: $lib"
        libs+=("$lib")
    done < <(static_library_paths "$build_dir" "$release_dir")

    log "combining static libraries for $platform"
    xcrun libtool -static -o "$combined_lib" "${libs[@]}" 2>/dev/null

    local sdk=""
    local archs=""
    local min_version_flag=""
    local install_name=""

    case "$platform" in
        ios-device)
            sdk="iphoneos"
            archs="arm64"
            min_version_flag="-mios-version-min=$IOS_MIN_OS_VERSION"
            install_name="@rpath/$LLAMA_APPLE_FRAMEWORK_NAME.framework/$LLAMA_APPLE_FRAMEWORK_NAME"
            ;;
        ios-simulator)
            sdk="iphonesimulator"
            archs="arm64 x86_64"
            min_version_flag="-mios-simulator-version-min=$IOS_MIN_OS_VERSION"
            install_name="@rpath/$LLAMA_APPLE_FRAMEWORK_NAME.framework/$LLAMA_APPLE_FRAMEWORK_NAME"
            ;;
        macos)
            sdk="macosx"
            archs="arm64 x86_64"
            min_version_flag="-mmacosx-version-min=$MACOS_MIN_OS_VERSION"
            install_name="@rpath/$LLAMA_APPLE_FRAMEWORK_NAME.framework/Versions/Current/$LLAMA_APPLE_FRAMEWORK_NAME"
            ;;
        *)
            die "unsupported platform: $platform"
            ;;
    esac

    local arch_flags=()
    local arch
    for arch in $archs; do
        arch_flags+=(-arch "$arch")
    done

    log "creating dynamic framework binary for $platform"
    xcrun -sdk "$sdk" clang++ -dynamiclib \
        -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
        "${arch_flags[@]}" \
        "$min_version_flag" \
        -Wl,-force_load,"$combined_lib" \
        -framework Foundation -framework Metal -framework Accelerate \
        -install_name "$install_name" \
        -o "$binary_path"

    mark_device_binary "$platform" "$binary_path" "$is_simulator"
    create_dsym_and_strip "$platform" "$build_dir" "$binary_path"
    rm -rf "$temp_dir"
}

mark_device_binary() {
    local platform="$1"
    local binary_path="$2"
    local is_simulator="$3"

    [[ "$is_simulator" == "false" ]] || return 0
    command -v xcrun >/dev/null 2>&1 || return 0
    xcrun -f vtool >/dev/null 2>&1 || return 0

    case "$platform" in
        ios-device)
            log "marking iOS framework binary"
            xcrun vtool -set-build-version ios "$IOS_MIN_OS_VERSION" "$IOS_MIN_OS_VERSION" -replace \
                -output "$binary_path" "$binary_path"
            ;;
        macos)
            ;;
    esac
}

create_dsym_and_strip() {
    local platform="$1"
    local build_dir="$2"
    local binary_path="$3"
    local dsym_dir="$build_dir/dSYMs/$LLAMA_APPLE_FRAMEWORK_NAME.dSYM"
    local temp_binary="$build_dir/temp/binary_to_strip"
    local stripped_binary="$build_dir/temp/stripped_binary"

    log "creating dSYM for $platform"
    mkdir -p "$build_dir/dSYMs" "$build_dir/temp"
    xcrun dsymutil "$binary_path" -o "$dsym_dir"
    cp "$binary_path" "$temp_binary"
    xcrun strip -S "$temp_binary" -o "$stripped_binary"
    mv "$stripped_binary" "$binary_path"

    if [[ -d "$binary_path.dSYM" ]]; then
        rm -rf "$binary_path.dSYM"
    fi
}

create_xcframework() {
    local args=()
    local platform

    while IFS= read -r platform; do
        local build_dir
        build_dir="$(platform_build_dir "$platform")"
        args+=(
            -framework "$build_dir/framework/$LLAMA_APPLE_FRAMEWORK_NAME.framework"
            -debug-symbols "$build_dir/dSYMs/$LLAMA_APPLE_FRAMEWORK_NAME.dSYM"
        )
    done < <(split_platforms)

    mkdir -p "$ARTIFACTS"
    rm -rf "$OUTPUT_XCFRAMEWORK"

    log "creating XCFramework"
    xcrun xcodebuild -create-xcframework "${args[@]}" -output "$OUTPUT_XCFRAMEWORK"
}

validate_checkout() {
    [[ -d "$CHECKOUT_DIR" ]] || die "missing upstream checkout: $CHECKOUT_DIR"
    [[ -f "$CHECKOUT_DIR/include/llama.h" ]] || die "missing upstream include/llama.h"
    [[ -f "$CHECKOUT_DIR/ggml/include/ggml.h" ]] || die "missing upstream ggml/include/ggml.h"
    [[ -f "$CHECKOUT_DIR/ggml/include/gguf.h" ]] || die "missing upstream ggml/include/gguf.h"
    [[ -f "$CHECKOUT_DIR/tools/mtmd/mtmd.h" ]] || die "missing upstream tools/mtmd/mtmd.h"
    [[ -f "$CHECKOUT_DIR/tools/mtmd/mtmd-helper.h" ]] || die "missing upstream tools/mtmd/mtmd-helper.h"
}

print_plan

if [[ "$DRY_RUN" -eq 1 ]]; then
    exit 0
fi

require_build_tools

if [[ "$CLEAN" -eq 1 ]]; then
    log "cleaning native build output"
    rm -rf "$BUILD_ROOT" "$OUTPUT_XCFRAMEWORK"
fi

if [[ "$SKIP_BOOTSTRAP" -eq 0 ]]; then
    "$ROOT/scripts/bootstrap-upstream.sh"
fi

validate_checkout

mkdir -p "$BUILD_ROOT" "$ARTIFACTS"

while IFS= read -r platform; do
    configure_platform "$platform"
    build_platform "$platform"
    setup_framework_structure "$platform"
    combine_static_libraries "$platform"
done < <(split_platforms)

create_xcframework
"$ROOT/scripts/verify-artifact.sh" "$OUTPUT_XCFRAMEWORK"

log "built $OUTPUT_XCFRAMEWORK"
