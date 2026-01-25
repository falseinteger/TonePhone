#!/bin/bash
#
# build-core.sh — Build libre and baresip for Apple platforms
#
# Builds the core SIP libraries as static libraries for:
#   - macOS arm64
#   - macOS x86_64
#   - iOS arm64 (device)
#   - iOS Simulator arm64
#   - iOS Simulator x86_64
#
# Note: librem (rem) functionality is built into libre by default (USE_REM=ON).
#
# Output: output/<platform>/lib/ and output/<platform>/include/
#
# Usage:
#   ./scripts/build-core.sh
#
# Requirements:
#   - Xcode Command Line Tools (full Xcode for iOS SDKs)
#   - CMake 3.20+
#   - Ninja 1.11+
#   - pkg-config
#   - OpenSSL built via build-openssl.sh
#

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"
BUILD_DIR="$PROJECT_ROOT/build"
OUTPUT_DIR="$PROJECT_ROOT/output"

# Deployment targets
MACOS_DEPLOYMENT_TARGET="12.0"
IOS_DEPLOYMENT_TARGET="15.0"

# Platforms to build
# Format: "name:sdk:arch"
PLATFORMS=(
    "macos-arm64:macosx:arm64"
    "macos-x86_64:macosx:x86_64"
    "ios-arm64:iphoneos:arm64"
    "ios-sim-arm64:iphonesimulator:arm64"
    "ios-sim-x86_64:iphonesimulator:x86_64"
)

# Baresip modules to enable (semicolon-separated for CMake)
# Note: opus module requires libopus to be cross-compiled for each platform.
# For now, opus is excluded. Create build-opus.sh (similar to build-openssl.sh) to enable it.
BARESIP_MODULES="audiounit;g711;stun;turn;ice;srtp;dtls_srtp;account"

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

    if ! command -v cmake &> /dev/null; then
        log_error "CMake not found. Install with: brew install cmake"
        exit 1
    fi

    if ! command -v ninja &> /dev/null; then
        log_error "Ninja not found. Install with: brew install ninja"
        exit 1
    fi

    if ! command -v pkg-config &> /dev/null; then
        log_error "pkg-config not found. Install with: brew install pkg-config"
        exit 1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode Command Line Tools not found. Install with: xcode-select --install"
        exit 1
    fi

    # Verify required SDKs are available
    local required_sdks=("macosx" "iphoneos" "iphonesimulator")
    for sdk in "${required_sdks[@]}"; do
        if ! xcrun --sdk "$sdk" --show-sdk-path &> /dev/null; then
            log_error "SDK '$sdk' not found. Install full Xcode (not just Command Line Tools)"
            exit 1
        fi
    done

    # Check submodules exist
    if [[ ! -f "$CORE_DIR/re/CMakeLists.txt" ]]; then
        log_error "Submodule core/re not found. Run: git submodule update --init --recursive"
        exit 1
    fi

    if [[ ! -f "$CORE_DIR/baresip/CMakeLists.txt" ]]; then
        log_error "Submodule core/baresip not found. Run: git submodule update --init --recursive"
        exit 1
    fi

    # Check OpenSSL is built
    for entry in "${PLATFORMS[@]}"; do
        IFS=':' read -r platform _ _ <<< "$entry"
        local openssl_path="$CORE_DIR/openssl/$platform"
        if [[ ! -f "$openssl_path/lib/libssl.a" ]] || [[ ! -f "$openssl_path/lib/libcrypto.a" ]]; then
            log_error "OpenSSL not found for $platform. Run: ./scripts/build-openssl.sh"
            exit 1
        fi
    done

    log_info "Prerequisites OK"
}

# Build libre for a single platform
# Note: libre includes librem functionality by default (USE_REM=ON)
build_libre() {
    local platform=$1
    local sdk=$2
    local arch=$3
    local build_path="$BUILD_DIR/$platform/re"
    local install_path="$OUTPUT_DIR/$platform"
    local openssl_path="$CORE_DIR/openssl/$platform"

    # Check if already built (idempotent)
    if [[ -f "$install_path/lib/libre.a" ]] && [[ -f "$install_path/include/re/re.h" ]]; then
        log_info "[$platform] libre already built, skipping"
        return 0
    fi

    log_info "[$platform] Building libre..."

    rm -rf "$build_path"
    mkdir -p "$build_path"

    local sdk_path
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)

    local system_name="Darwin"
    local deployment_target="$MACOS_DEPLOYMENT_TARGET"
    if [[ "$sdk" != "macosx" ]]; then
        system_name="iOS"
        deployment_target="$IOS_DEPLOYMENT_TARGET"
    fi

    local log_file="$BUILD_DIR/build-libre-$platform.log"

    if ! cmake -S "$CORE_DIR/re" -B "$build_path" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME="$system_name" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DCMAKE_INSTALL_PREFIX="$install_path" \
        -DOPENSSL_ROOT_DIR="$openssl_path" \
        -DOPENSSL_INCLUDE_DIR="$openssl_path/include" \
        -DOPENSSL_SSL_LIBRARY="$openssl_path/lib/libssl.a" \
        -DOPENSSL_CRYPTO_LIBRARY="$openssl_path/lib/libcrypto.a" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DLIBRE_BUILD_SHARED=OFF \
        -DLIBRE_BUILD_STATIC=ON \
        -DUSE_OPENSSL=ON \
        -DUSE_REM=ON \
        > "$log_file" 2>&1; then
        log_error "[$platform] libre configure failed. See log: $log_file"
        tail -30 "$log_file"
        exit 1
    fi

    if ! cmake --build "$build_path" --parallel >> "$log_file" 2>&1; then
        log_error "[$platform] libre build failed. See log: $log_file"
        tail -30 "$log_file"
        exit 1
    fi

    if ! cmake --install "$build_path" >> "$log_file" 2>&1; then
        log_error "[$platform] libre install failed. See log: $log_file"
        tail -30 "$log_file"
        exit 1
    fi

    log_info "[$platform] libre build complete"
}

# Build baresip for a single platform
build_baresip() {
    local platform=$1
    local sdk=$2
    local arch=$3
    local build_path="$BUILD_DIR/$platform/baresip"
    local install_path="$OUTPUT_DIR/$platform"
    local openssl_path="$CORE_DIR/openssl/$platform"

    # Check if already built (idempotent)
    if [[ -f "$install_path/lib/libbaresip.a" ]] && [[ -f "$install_path/include/baresip.h" ]]; then
        log_info "[$platform] baresip already built, skipping"
        return 0
    fi

    log_info "[$platform] Building baresip..."

    rm -rf "$build_path"
    mkdir -p "$build_path"

    local sdk_path
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)

    local system_name="Darwin"
    local deployment_target="$MACOS_DEPLOYMENT_TARGET"
    if [[ "$sdk" != "macosx" ]]; then
        system_name="iOS"
        deployment_target="$IOS_DEPLOYMENT_TARGET"
    fi

    local log_file="$BUILD_DIR/build-baresip-$platform.log"

    if ! cmake -S "$CORE_DIR/baresip" -B "$build_path" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME="$system_name" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DCMAKE_INSTALL_PREFIX="$install_path" \
        -DCMAKE_PREFIX_PATH="$install_path" \
        -Dre_DIR="$install_path/lib/cmake/re" \
        -DRE_INCLUDE_DIR="$install_path/include/re" \
        -DRE_LIBRARY="$install_path/lib/libre.a" \
        -DOPENSSL_ROOT_DIR="$openssl_path" \
        -DOPENSSL_INCLUDE_DIR="$openssl_path/include" \
        -DOPENSSL_SSL_LIBRARY="$openssl_path/lib/libssl.a" \
        -DOPENSSL_CRYPTO_LIBRARY="$openssl_path/lib/libcrypto.a" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DSTATIC=ON \
        -DMODULES="$BARESIP_MODULES" \
        -DCMAKE_MACOSX_BUNDLE=OFF \
        > "$log_file" 2>&1; then
        log_error "[$platform] baresip configure failed. See log: $log_file"
        tail -30 "$log_file"
        exit 1
    fi

    # Build only the library target (skip executable which has iOS linking issues)
    # Note: cmake --build may fail at the end when linking executable, but library is built
    cmake --build "$build_path" --target baresip --parallel >> "$log_file" 2>&1 || true

    # Verify library was built
    if [[ ! -f "$build_path/libbaresip.a" ]]; then
        log_error "[$platform] baresip build failed - library not found. See log: $log_file"
        tail -30 "$log_file"
        exit 1
    fi

    # Manual install: copy library and headers (skip cmake --install due to iOS bundle issues)
    mkdir -p "$install_path/lib" "$install_path/include"
    cp "$build_path/libbaresip.a" "$install_path/lib/"
    cp "$CORE_DIR/baresip/include/baresip.h" "$install_path/include/"

    log_info "[$platform] baresip build complete"
}

# Main
main() {
    log_info "=== Core Libraries Build Script ==="
    log_info "Output: $OUTPUT_DIR"
    echo

    check_prerequisites

    echo
    log_info "Building for ${#PLATFORMS[@]} platforms..."
    echo

    mkdir -p "$BUILD_DIR"

    for entry in "${PLATFORMS[@]}"; do
        IFS=':' read -r platform sdk arch <<< "$entry"

        # Build in dependency order: libre (includes rem) → baresip
        build_libre "$platform" "$sdk" "$arch"
        build_baresip "$platform" "$sdk" "$arch"
        echo
    done

    echo
    log_info "=== Build Summary ==="
    for entry in "${PLATFORMS[@]}"; do
        IFS=':' read -r platform _ _ <<< "$entry"
        local install_path="$OUTPUT_DIR/$platform"
        if [[ -f "$install_path/lib/libre.a" ]] && \
           [[ -f "$install_path/lib/libbaresip.a" ]]; then
            local size
            size=$(du -sh "$install_path/lib" | awk '{print $1}')
            echo -e "  ${GREEN}✓${NC} $platform ($size)"
        else
            echo -e "  ${RED}✗${NC} $platform (incomplete)"
        fi
    done

    echo
    log_info "Done!"
}

main "$@"
