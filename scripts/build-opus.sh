#!/bin/bash
#
# build-opus.sh — Build libopus for Apple platforms
#
# Builds libopus as static libraries for:
#   - macOS arm64
#   - macOS x86_64
#   - iOS arm64 (device)
#   - iOS Simulator arm64
#   - iOS Simulator x86_64
#
# Output: core/opus/<platform>/lib/ and core/opus/<platform>/include/
#
# Usage:
#   ./scripts/build-opus.sh
#
# Requirements:
#   - Xcode Command Line Tools
#   - curl (for downloading)
#

set -euo pipefail

# Configuration
OPUS_VERSION="1.5.2"
# SHA256 from: https://github.com/xiph/opus/releases/tag/v1.5.2
OPUS_SHA256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"

# Deployment targets
MACOS_MIN_VERSION="12.0"
IOS_MIN_VERSION="15.0"

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPUS_DIR="$PROJECT_ROOT/core/opus"
BUILD_DIR="$PROJECT_ROOT/build/opus"
SOURCE_DIR="$BUILD_DIR/opus-$OPUS_VERSION"
TARBALL="$BUILD_DIR/opus-$OPUS_VERSION.tar.gz"

# Platforms to build
# Format: "name:arch:sdk:host"
PLATFORMS=(
    "macos-arm64:arm64:macosx:aarch64-apple-darwin"
    "macos-x86_64:x86_64:macosx:x86_64-apple-darwin"
    "ios-arm64:arm64:iphoneos:aarch64-apple-darwin"
    "ios-sim-arm64:arm64:iphonesimulator:aarch64-apple-darwin"
    "ios-sim-x86_64:x86_64:iphonesimulator:x86_64-apple-darwin"
)

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

    if ! command -v curl &> /dev/null; then
        log_error "curl not found"
        exit 1
    fi

    if ! command -v make &> /dev/null; then
        log_error "make not found. Install Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi

    # Verify required SDKs are available (need full Xcode, not just CLI Tools)
    local required_sdks=("macosx" "iphoneos" "iphonesimulator")
    for sdk in "${required_sdks[@]}"; do
        if ! xcrun --sdk "$sdk" --show-sdk-path &> /dev/null; then
            log_error "SDK '$sdk' not found. Install full Xcode (not just Command Line Tools)"
            exit 1
        fi
    done

    log_info "Prerequisites OK"
}

# Download Opus source
download_opus() {
    mkdir -p "$BUILD_DIR"

    if [[ -f "$TARBALL" ]]; then
        log_info "Opus tarball already exists, verifying checksum..."
        local actual_sha256
        actual_sha256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
        if [[ "$actual_sha256" == "$OPUS_SHA256" ]]; then
            log_info "Checksum OK, skipping download"
            return 0
        else
            log_warn "Checksum mismatch, re-downloading..."
            rm -f "$TARBALL"
        fi
    fi

    log_info "Downloading Opus $OPUS_VERSION..."
    if ! curl --fail -L -o "$TARBALL" \
        "https://github.com/xiph/opus/releases/download/v$OPUS_VERSION/opus-$OPUS_VERSION.tar.gz"; then
        log_error "Failed to download Opus $OPUS_VERSION"
        log_error "Check your network connection and try again"
        rm -f "$TARBALL"
        exit 1
    fi

    log_info "Verifying checksum..."
    local actual_sha256
    actual_sha256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
    if [[ "$actual_sha256" != "$OPUS_SHA256" ]]; then
        log_error "Checksum verification failed!"
        log_error "Expected: $OPUS_SHA256"
        log_error "Actual:   $actual_sha256"
        exit 1
    fi

    log_info "Checksum OK"
}

# Extract Opus source
extract_opus() {
    if [[ -d "$SOURCE_DIR" ]]; then
        log_info "Source directory exists, skipping extraction"
        return 0
    fi

    log_info "Extracting Opus..."
    tar -xzf "$TARBALL" -C "$BUILD_DIR"
}

# Build for a single platform
build_platform() {
    local name=$1
    local arch=$2
    local sdk=$3
    local host=$4

    local install_dir="$OPUS_DIR/$name"
    local build_dir="$BUILD_DIR/build-$name"

    # Check if already built (libs and headers must both exist)
    if [[ -f "$install_dir/lib/libopus.a" ]] && \
       [[ -f "$install_dir/include/opus/opus.h" ]]; then
        log_info "[$name] Already built, skipping"
        return 0
    fi

    log_info "[$name] Building Opus..."

    # Clean build directory
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    # Get SDK path
    local sdk_path
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)

    # Get compiler paths
    local cc
    cc=$(xcrun --sdk "$sdk" --find clang)
    local cxx
    cxx=$(xcrun --sdk "$sdk" --find clang++)

    # Build CFLAGS
    local cflags="-arch $arch -isysroot $sdk_path -O2"
    if [[ "$sdk" == "macosx" ]]; then
        cflags+=" -mmacosx-version-min=$MACOS_MIN_VERSION"
    elif [[ "$sdk" == "iphoneos" ]]; then
        cflags+=" -mios-version-min=$IOS_MIN_VERSION"
    elif [[ "$sdk" == "iphonesimulator" ]]; then
        cflags+=" -mios-simulator-version-min=$IOS_MIN_VERSION"
    fi

    local ldflags="-arch $arch -isysroot $sdk_path"

    cd "$SOURCE_DIR"

    # Configure
    local log_file="$BUILD_DIR/build-$name.log"

    # Run configure with cross-compilation settings
    if ! CC="$cc" CXX="$cxx" CFLAGS="$cflags" CXXFLAGS="$cflags" LDFLAGS="$ldflags" \
        ./configure \
            --host="$host" \
            --prefix="$install_dir" \
            --disable-shared \
            --enable-static \
            --disable-doc \
            --disable-extra-programs \
        > "$log_file" 2>&1; then
        log_error "[$name] Configure failed. See log: $log_file"
        tail -30 "$log_file"
        exit 1
    fi

    # Build
    if ! make -j"$(sysctl -n hw.ncpu)" >> "$log_file" 2>&1; then
        log_error "[$name] Build failed. See log: $log_file"
        tail -50 "$log_file"
        exit 1
    fi

    # Install
    if ! make install >> "$log_file" 2>&1; then
        log_error "[$name] Install failed. See log: $log_file"
        tail -30 "$log_file"
        exit 1
    fi

    # Clean for next build
    make distclean >> "$log_file" 2>&1 || true

    cd "$PROJECT_ROOT"

    log_info "[$name] Build complete"
}

# Main
main() {
    log_info "=== Opus Build Script ==="
    log_info "Version: $OPUS_VERSION"
    log_info "Output:  $OPUS_DIR"
    echo

    check_prerequisites
    download_opus
    extract_opus

    echo
    log_info "Building for ${#PLATFORMS[@]} platforms..."
    echo

    for platform in "${PLATFORMS[@]}"; do
        IFS=':' read -r name arch sdk host <<< "$platform"
        build_platform "$name" "$arch" "$sdk" "$host"
    done

    echo
    log_info "=== Build Summary ==="
    for platform in "${PLATFORMS[@]}"; do
        IFS=':' read -r name _ _ _ <<< "$platform"
        local install_dir="$OPUS_DIR/$name"
        if [[ -f "$install_dir/lib/libopus.a" ]] && \
           [[ -f "$install_dir/include/opus/opus.h" ]]; then
            local size
            size=$(du -sh "$install_dir/lib" | awk '{print $1}')
            echo -e "  ${GREEN}✓${NC} $name ($size)"
        else
            echo -e "  ${RED}✗${NC} $name (missing)"
        fi
    done

    echo
    log_info "Done!"
}

main "$@"
