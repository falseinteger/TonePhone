#!/bin/bash
#
# package-xcframework.sh — Package static libraries into XCFrameworks
#
# Creates universal (fat) libraries and packages them into XCFrameworks
# for Xcode integration.
#
# Creates:
#   - libre.xcframework (includes rem functionality)
#   - libbaresip.xcframework
#
# Output: output/xcframeworks/
#
# Usage:
#   ./scripts/package-xcframework.sh
#
# Requirements:
#   - Xcode Command Line Tools
#   - Libraries built via build-core.sh
#

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output"
XCFW_DIR="$OUTPUT_DIR/xcframeworks"

# Platform directories
MACOS_ARM64="$OUTPUT_DIR/macos-arm64"
MACOS_X86_64="$OUTPUT_DIR/macos-x86_64"
IOS_ARM64="$OUTPUT_DIR/ios-arm64"
IOS_SIM_ARM64="$OUTPUT_DIR/ios-sim-arm64"
IOS_SIM_X86_64="$OUTPUT_DIR/ios-sim-x86_64"

# Fat library directories
MACOS_FAT="$OUTPUT_DIR/macos-fat"
IOS_SIM_FAT="$OUTPUT_DIR/ios-sim-fat"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode Command Line Tools not found. Install with: xcode-select --install"
        exit 1
    fi

    if ! command -v lipo &> /dev/null; then
        log_error "lipo not found. Install Xcode Command Line Tools."
        exit 1
    fi

    # Check that libraries exist for all platforms
    local platforms=("$MACOS_ARM64" "$MACOS_X86_64" "$IOS_ARM64" "$IOS_SIM_ARM64" "$IOS_SIM_X86_64")
    for platform_dir in "${platforms[@]}"; do
        local platform_name
        platform_name=$(basename "$platform_dir")
        if [[ ! -f "$platform_dir/lib/libre.a" ]]; then
            log_error "libre.a not found for $platform_name. Run: ./scripts/build-core.sh"
            exit 1
        fi
        if [[ ! -f "$platform_dir/lib/libbaresip.a" ]]; then
            log_error "libbaresip.a not found for $platform_name. Run: ./scripts/build-core.sh"
            exit 1
        fi
    done

    log_info "Prerequisites OK"
}

# Create fat library for macOS (arm64 + x86_64)
create_macos_fat_lib() {
    local lib_name=$1
    local fat_dir="$MACOS_FAT/lib"
    mkdir -p "$fat_dir"

    log_info "Creating macOS fat library: $lib_name"
    lipo -create \
        "$MACOS_ARM64/lib/$lib_name" \
        "$MACOS_X86_64/lib/$lib_name" \
        -output "$fat_dir/$lib_name"
}

# Create fat library for iOS Simulator (arm64 + x86_64)
create_sim_fat_lib() {
    local lib_name=$1
    local fat_dir="$IOS_SIM_FAT/lib"
    mkdir -p "$fat_dir"

    log_info "Creating iOS Simulator fat library: $lib_name"
    lipo -create \
        "$IOS_SIM_ARM64/lib/$lib_name" \
        "$IOS_SIM_X86_64/lib/$lib_name" \
        -output "$fat_dir/$lib_name"
}

# Copy headers for fat library directories
copy_headers() {
    log_info "Copying headers..."

    # Copy from arm64 builds (headers are identical across architectures)
    mkdir -p "$MACOS_FAT/include"
    mkdir -p "$IOS_SIM_FAT/include"

    # Copy re headers
    if [[ -d "$MACOS_ARM64/include/re" ]]; then
        cp -R "$MACOS_ARM64/include/re" "$MACOS_FAT/include/"
    fi
    if [[ -d "$IOS_SIM_ARM64/include/re" ]]; then
        cp -R "$IOS_SIM_ARM64/include/re" "$IOS_SIM_FAT/include/"
    fi

    # Copy baresip header
    if [[ -f "$MACOS_ARM64/include/baresip.h" ]]; then
        cp "$MACOS_ARM64/include/baresip.h" "$MACOS_FAT/include/"
    fi
    if [[ -f "$IOS_SIM_ARM64/include/baresip.h" ]]; then
        cp "$IOS_SIM_ARM64/include/baresip.h" "$IOS_SIM_FAT/include/"
    fi
}

# Create XCFramework for libre
create_libre_xcframework() {
    log_info "Creating libre.xcframework..."

    # Prepare header directories for each platform
    # XCFrameworks need headers alongside each library slice
    local macos_headers="$MACOS_FAT/include"
    local ios_headers="$IOS_ARM64/include"
    local sim_headers="$IOS_SIM_FAT/include"

    xcodebuild -create-xcframework \
        -library "$MACOS_FAT/lib/libre.a" \
        -headers "$macos_headers" \
        -library "$IOS_ARM64/lib/libre.a" \
        -headers "$ios_headers" \
        -library "$IOS_SIM_FAT/lib/libre.a" \
        -headers "$sim_headers" \
        -output "$XCFW_DIR/libre.xcframework"
}

# Create XCFramework for libbaresip
create_baresip_xcframework() {
    log_info "Creating libbaresip.xcframework..."

    local macos_headers="$MACOS_FAT/include"
    local ios_headers="$IOS_ARM64/include"
    local sim_headers="$IOS_SIM_FAT/include"

    xcodebuild -create-xcframework \
        -library "$MACOS_FAT/lib/libbaresip.a" \
        -headers "$macos_headers" \
        -library "$IOS_ARM64/lib/libbaresip.a" \
        -headers "$ios_headers" \
        -library "$IOS_SIM_FAT/lib/libbaresip.a" \
        -headers "$sim_headers" \
        -output "$XCFW_DIR/libbaresip.xcframework"
}

# Verify XCFramework structure
verify_xcframeworks() {
    log_info "Verifying XCFrameworks..."

    local has_errors=false

    for xcfw in "$XCFW_DIR"/*.xcframework; do
        local name
        name=$(basename "$xcfw")

        if [[ ! -d "$xcfw" ]]; then
            log_error "$name is not a valid directory"
            has_errors=true
            continue
        fi

        # Check for expected platform slices
        local expected_slices=("macos-arm64_x86_64" "ios-arm64" "ios-arm64_x86_64-simulator")
        for slice in "${expected_slices[@]}"; do
            if [[ ! -d "$xcfw/$slice" ]]; then
                log_error "$name missing slice: $slice"
                has_errors=true
            fi
        done

        # Verify Info.plist exists
        if [[ ! -f "$xcfw/Info.plist" ]]; then
            log_error "$name missing Info.plist"
            has_errors=true
        fi
    done

    if [[ "$has_errors" == "true" ]]; then
        log_error "XCFramework verification failed"
        exit 1
    fi

    log_info "XCFrameworks verified OK"
}

# Main
main() {
    log_info "=== XCFramework Packaging Script ==="
    log_info "Output: $XCFW_DIR"
    echo

    check_prerequisites

    # Clean previous output
    log_info "Cleaning previous XCFramework output..."
    rm -rf "$XCFW_DIR"
    rm -rf "$MACOS_FAT"
    rm -rf "$IOS_SIM_FAT"
    mkdir -p "$XCFW_DIR"

    echo
    log_info "Creating fat libraries..."
    echo

    # Create fat libraries
    create_macos_fat_lib "libre.a"
    create_macos_fat_lib "libbaresip.a"
    create_sim_fat_lib "libre.a"
    create_sim_fat_lib "libbaresip.a"

    # Copy headers
    copy_headers

    echo
    log_info "Creating XCFrameworks..."
    echo

    # Create XCFrameworks
    create_libre_xcframework
    create_baresip_xcframework

    echo
    verify_xcframeworks

    echo
    log_info "=== Build Summary ==="
    for xcfw in "$XCFW_DIR"/*.xcframework; do
        local name
        name=$(basename "$xcfw")
        local size
        size=$(du -sh "$xcfw" | awk '{print $1}')
        echo -e "  ${GREEN}✓${NC} $name ($size)"
    done

    echo
    log_info "Done!"
    log_info "XCFrameworks are ready at: $XCFW_DIR"
}

main "$@"
