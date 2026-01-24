#!/bin/bash
#
# build-openssl.sh — Build OpenSSL for Apple platforms
#
# Builds OpenSSL 3.x as static libraries for:
#   - macOS arm64
#   - macOS x86_64
#   - iOS arm64 (device)
#   - iOS Simulator arm64
#   - iOS Simulator x86_64
#
# Output: core/openssl/<platform>/lib/ and core/openssl/<platform>/include/
#
# Usage:
#   ./scripts/build-openssl.sh
#
# Requirements:
#   - Xcode Command Line Tools
#   - curl (for downloading)
#

set -euo pipefail

# Configuration
OPENSSL_VERSION="3.4.1"
# SHA256 from OpenSSL release: https://github.com/openssl/openssl/releases/tag/openssl-3.4.1
OPENSSL_SHA256="002a2d6b30b58bf4bea46c43bdd96365aaf8daa6c428782aa4feee06da197df3"

# Deployment targets
MACOS_MIN_VERSION="12.0"
IOS_MIN_VERSION="15.0"

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENSSL_DIR="$PROJECT_ROOT/core/openssl"
BUILD_DIR="$PROJECT_ROOT/build/openssl"
SOURCE_DIR="$BUILD_DIR/openssl-$OPENSSL_VERSION"
TARBALL="$BUILD_DIR/openssl-$OPENSSL_VERSION.tar.gz"

# Platforms to build
# Format: "name:target:arch:sdk"
PLATFORMS=(
    "macos-arm64:darwin64-arm64-cc:arm64:macosx"
    "macos-x86_64:darwin64-x86_64-cc:x86_64:macosx"
    "ios-arm64:ios64-xcrun:arm64:iphoneos"
    "ios-sim-arm64:iossimulator-xcrun:arm64:iphonesimulator"
    "ios-sim-x86_64:iossimulator-xcrun:x86_64:iphonesimulator"
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

    log_info "Prerequisites OK"
}

# Download OpenSSL source
download_openssl() {
    mkdir -p "$BUILD_DIR"

    if [[ -f "$TARBALL" ]]; then
        log_info "OpenSSL tarball already exists, verifying checksum..."
        local actual_sha256
        actual_sha256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
        if [[ "$actual_sha256" == "$OPENSSL_SHA256" ]]; then
            log_info "Checksum OK, skipping download"
            return 0
        else
            log_warn "Checksum mismatch, re-downloading..."
            rm -f "$TARBALL"
        fi
    fi

    log_info "Downloading OpenSSL $OPENSSL_VERSION..."
    if ! curl --fail -L -o "$TARBALL" \
        "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"; then
        log_error "Failed to download OpenSSL $OPENSSL_VERSION"
        log_error "Check your network connection and try again"
        rm -f "$TARBALL"
        exit 1
    fi

    log_info "Verifying checksum..."
    local actual_sha256
    actual_sha256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
    if [[ "$actual_sha256" != "$OPENSSL_SHA256" ]]; then
        log_error "Checksum verification failed!"
        log_error "Expected: $OPENSSL_SHA256"
        log_error "Actual:   $actual_sha256"
        exit 1
    fi

    log_info "Checksum OK"
}

# Extract OpenSSL source
extract_openssl() {
    if [[ -d "$SOURCE_DIR" ]]; then
        log_info "Source directory exists, skipping extraction"
        return 0
    fi

    log_info "Extracting OpenSSL..."
    tar -xzf "$TARBALL" -C "$BUILD_DIR"
}

# Build for a single platform
build_platform() {
    local name=$1
    local target=$2
    local arch=$3
    local sdk=$4

    local install_dir="$OPENSSL_DIR/$name"
    local build_dir="$BUILD_DIR/build-$name"

    # Check if already built
    if [[ -f "$install_dir/lib/libssl.a" && -f "$install_dir/lib/libcrypto.a" ]]; then
        log_info "[$name] Already built, skipping"
        return 0
    fi

    log_info "[$name] Building OpenSSL..."

    # Clean build directory
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    # Copy source to build directory (OpenSSL builds in-place)
    cp -R "$SOURCE_DIR"/* "$build_dir/"

    cd "$build_dir"

    # Get SDK path
    local sdk_path
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)

    # Set up environment
    export CROSS_TOP="${sdk_path%/SDKs/*}"
    export CROSS_SDK="${sdk_path##*/}"

    # Configure based on platform
    local configure_args=(
        "$target"
        no-shared
        no-tests
        no-ui-console
        "--prefix=$install_dir"
    )

    # Build CFLAGS with deployment target and arch flags
    local cflags=""
    if [[ "$sdk" == "macosx" ]]; then
        cflags="-mmacosx-version-min=$MACOS_MIN_VERSION"
    elif [[ "$sdk" == "iphoneos" ]]; then
        cflags="-mios-version-min=$IOS_MIN_VERSION"
    elif [[ "$sdk" == "iphonesimulator" ]]; then
        cflags="-mios-simulator-version-min=$IOS_MIN_VERSION -arch $arch"
    fi

    # Configure with CFLAGS
    CFLAGS="$cflags" ./Configure "${configure_args[@]}"

    # Build (redirect output to log file, show on failure)
    local log_file="$BUILD_DIR/build-$name.log"
    if ! make -j"$(sysctl -n hw.ncpu)" > "$log_file" 2>&1; then
        log_error "[$name] Build failed. See log: $log_file"
        tail -50 "$log_file"
        exit 1
    fi

    # Install (only libraries and headers)
    if ! make install_sw >> "$log_file" 2>&1; then
        log_error "[$name] Install failed. See log: $log_file"
        tail -50 "$log_file"
        exit 1
    fi

    cd "$PROJECT_ROOT"

    # Clean up build directory to save space
    rm -rf "$build_dir"

    log_info "[$name] Build complete"
}

# Main
main() {
    log_info "=== OpenSSL Build Script ==="
    log_info "Version: $OPENSSL_VERSION"
    log_info "Output:  $OPENSSL_DIR"
    echo

    check_prerequisites
    download_openssl
    extract_openssl

    echo
    log_info "Building for ${#PLATFORMS[@]} platforms..."
    echo

    for platform in "${PLATFORMS[@]}"; do
        IFS=':' read -r name target arch sdk <<< "$platform"
        build_platform "$name" "$target" "$arch" "$sdk"
    done

    echo
    log_info "=== Build Summary ==="
    for platform in "${PLATFORMS[@]}"; do
        IFS=':' read -r name _ _ _ <<< "$platform"
        local install_dir="$OPENSSL_DIR/$name"
        if [[ -f "$install_dir/lib/libssl.a" ]]; then
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
