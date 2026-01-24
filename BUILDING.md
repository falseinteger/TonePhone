# BUILDING.md — TonePhone Core Libraries

This document describes how to build **baresip**, **libre (re)**, and **librem (rem)** as static libraries for Apple platforms, package them into XCFrameworks, and integrate them into Xcode projects.

---

## Goals

- Build baresip and dependencies from source
- Produce static libraries (`.a`) for all target architectures
- Package into XCFrameworks for clean Xcode integration
- Keep the build minimal, reproducible, and auditable
- Support macOS (arm64, x86_64) and iOS (device + simulator)

---

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| macOS | 14.0+ | Build host |
| Xcode | 15.0+ | Command line tools required |
| CMake | 3.20+ | `brew install cmake` |
| Ninja | 1.11+ | `brew install ninja` |
| pkg-config | 0.29+ | `brew install pkg-config` |
| OpenSSL | 3.x | See setup below |

Verify Xcode command line tools:

```bash
xcode-select -p
# Should print /Applications/Xcode.app/Contents/Developer
```

---

## Repository Layout

```
tonephone/
├── core/
│   ├── re/                    # libre source (git submodule)
│   ├── rem/                   # librem source (git submodule)
│   ├── baresip/               # baresip source (git submodule)
│   └── openssl/               # OpenSSL builds per platform (created by build)
├── build/
│   ├── macos-arm64/
│   ├── macos-x86_64/
│   ├── ios-arm64/
│   ├── ios-sim-arm64/
│   └── ios-sim-x86_64/
├── output/
│   ├── lib/                   # Platform-specific static libraries
│   └── xcframeworks/          # Final XCFrameworks
├── scripts/
│   ├── build-core.sh          # Main build script
│   ├── build-openssl.sh       # OpenSSL build helper
│   └── package-xcframework.sh # XCFramework packaging
└── apps/
    ├── macOS/
    └── iOS/
```

Clone with submodules:

```bash
git clone --recursive https://github.com/user/tonephone.git
cd tonephone
```

Or initialize submodules after clone:

```bash
git submodule update --init --recursive
```

---

## Modules and Features

TonePhone builds baresip with a minimal, audio-focused module set.

### Enabled Modules

| Category | Modules |
|----------|---------|
| Audio I/O | `audiounit` (macOS/iOS native) |
| Audio Codecs | `opus`, `g711` |
| NAT Traversal | `stun`, `turn`, `ice` |
| Security | `srtp`, `dtls_srtp` |
| Account | `account` |

### Disabled / Not Built

- All video modules
- Platform-specific drivers (ALSA, PulseAudio, etc.)
- UI modules (stdio, menu, gtk)
- Messaging, presence, MWI
- Experimental codecs

Module selection is controlled via CMake options in the build script.

---

## OpenSSL Setup

baresip requires OpenSSL for TLS and SRTP. Apple platforms do not ship OpenSSL headers, so we build or provide our own.

### Option A: Pre-built OpenSSL (Recommended)

Use a pre-built OpenSSL XCFramework or static libraries. Several options:

1. **OpenSSL for Apple** — https://github.com/nicklockwood/OpenSSL
2. **Build using openssl-apple script** — https://github.com/nicklockwood/openssl-apple

Place the built libraries in:

```
core/openssl/
├── macos-arm64/
│   ├── include/openssl/
│   ├── lib/libssl.a
│   └── lib/libcrypto.a
├── macos-x86_64/
│   └── ...
├── ios-arm64/
│   └── ...
├── ios-sim-arm64/
│   └── ...
└── ios-sim-x86_64/
    └── ...
```

### Option B: Build OpenSSL Yourself

```bash
# Example for macOS arm64
export CROSS_TOP=$(xcrun --sdk macosx --show-sdk-platform-path)/Developer
export CROSS_SDK=$(xcrun --sdk macosx --show-sdk-path | xargs basename)

cd /path/to/openssl-source
./Configure darwin64-arm64-cc no-shared no-tests \
    --prefix=/path/to/tonephone/core/openssl/macos-arm64
make -j$(sysctl -n hw.ncpu)
make install_sw
```

Repeat for each architecture with appropriate target:
- `darwin64-arm64-cc` — macOS arm64
- `darwin64-x86_64-cc` — macOS x86_64
- `ios64-xcrun` — iOS device arm64
- `iossimulator-xcrun` — iOS simulator

---

## Build Strategy

Each library (re, rem, baresip) is built separately for each platform/architecture combination, then combined into fat libraries or XCFrameworks.

### Target Matrix

| Platform | Architecture | SDK | Deployment Target |
|----------|--------------|-----|-------------------|
| macOS | arm64 | macosx | 12.0 |
| macOS | x86_64 | macosx | 12.0 |
| iOS Device | arm64 | iphoneos | 15.0 |
| iOS Simulator | arm64 | iphonesimulator | 15.0 |
| iOS Simulator | x86_64 | iphonesimulator | 15.0 |

### Build Order

Dependencies must be built in order:

1. **libre (re)** — core library, no dependencies except OpenSSL
2. **librem (rem)** — depends on libre
3. **baresip** — depends on libre and librem

---

## Build Script

Create `scripts/build-core.sh`:

```bash
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"
BUILD_DIR="$PROJECT_ROOT/build"
OUTPUT_DIR="$PROJECT_ROOT/output"

# Deployment targets
MACOS_DEPLOYMENT_TARGET="12.0"
IOS_DEPLOYMENT_TARGET="15.0"

# Platforms to build
PLATFORMS=(
    "macos-arm64:macosx:arm64"
    "macos-x86_64:macosx:x86_64"
    "ios-arm64:iphoneos:arm64"
    "ios-sim-arm64:iphonesimulator:arm64"
    "ios-sim-x86_64:iphonesimulator:x86_64"
)

# Baresip modules to enable
BARESIP_MODULES="audiounit;opus;g711;stun;turn;ice;srtp;dtls_srtp;account"

build_libre() {
    local platform=$1
    local sdk=$2
    local arch=$3
    local build_path="$BUILD_DIR/$platform/re"
    local install_path="$OUTPUT_DIR/$platform"
    local openssl_path="$CORE_DIR/openssl/$platform"

    echo "=== Building libre for $platform ($arch) ==="

    rm -rf "$build_path"
    mkdir -p "$build_path"

    local sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    local deployment_flag=""

    if [[ "$sdk" == "macosx" ]]; then
        deployment_flag="-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET"
    else
        deployment_flag="-DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET"
    fi

    cmake -S "$CORE_DIR/re" -B "$build_path" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=$([ "$sdk" == "macosx" ] && echo "Darwin" || echo "iOS") \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        $deployment_flag \
        -DCMAKE_INSTALL_PREFIX="$install_path" \
        -DOPENSSL_ROOT_DIR="$openssl_path" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DUSE_OPENSSL=ON

    cmake --build "$build_path" --parallel
    cmake --install "$build_path"
}

build_librem() {
    local platform=$1
    local sdk=$2
    local arch=$3
    local build_path="$BUILD_DIR/$platform/rem"
    local install_path="$OUTPUT_DIR/$platform"

    echo "=== Building librem for $platform ($arch) ==="

    rm -rf "$build_path"
    mkdir -p "$build_path"

    local sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    local deployment_flag=""

    if [[ "$sdk" == "macosx" ]]; then
        deployment_flag="-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET"
    else
        deployment_flag="-DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET"
    fi

    cmake -S "$CORE_DIR/rem" -B "$build_path" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=$([ "$sdk" == "macosx" ] && echo "Darwin" || echo "iOS") \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        $deployment_flag \
        -DCMAKE_INSTALL_PREFIX="$install_path" \
        -DCMAKE_PREFIX_PATH="$install_path" \
        -DBUILD_SHARED_LIBS=OFF

    cmake --build "$build_path" --parallel
    cmake --install "$build_path"
}

build_baresip() {
    local platform=$1
    local sdk=$2
    local arch=$3
    local build_path="$BUILD_DIR/$platform/baresip"
    local install_path="$OUTPUT_DIR/$platform"
    local openssl_path="$CORE_DIR/openssl/$platform"

    echo "=== Building baresip for $platform ($arch) ==="

    rm -rf "$build_path"
    mkdir -p "$build_path"

    local sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    local deployment_flag=""

    if [[ "$sdk" == "macosx" ]]; then
        deployment_flag="-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET"
    else
        deployment_flag="-DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET"
    fi

    cmake -S "$CORE_DIR/baresip" -B "$build_path" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=$([ "$sdk" == "macosx" ] && echo "Darwin" || echo "iOS") \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        $deployment_flag \
        -DCMAKE_INSTALL_PREFIX="$install_path" \
        -DCMAKE_PREFIX_PATH="$install_path" \
        -DOPENSSL_ROOT_DIR="$openssl_path" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DSTATIC=ON \
        -DMODULES="$BARESIP_MODULES"

    cmake --build "$build_path" --parallel
    cmake --install "$build_path"
}

# Main build loop
for entry in "${PLATFORMS[@]}"; do
    IFS=':' read -r platform sdk arch <<< "$entry"

    build_libre "$platform" "$sdk" "$arch"
    build_librem "$platform" "$sdk" "$arch"
    build_baresip "$platform" "$sdk" "$arch"
done

echo "=== Build complete ==="
echo "Output: $OUTPUT_DIR"
```

Make executable and run:

```bash
chmod +x scripts/build-core.sh
./scripts/build-core.sh
```

---

## XCFramework Packaging

After building all platforms, package into XCFrameworks.

Create `scripts/package-xcframework.sh`:

```bash
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output"
XCFW_DIR="$OUTPUT_DIR/xcframeworks"

rm -rf "$XCFW_DIR"
mkdir -p "$XCFW_DIR"

# Create fat library for iOS Simulator (arm64 + x86_64)
create_sim_fat_lib() {
    local lib_name=$1
    local fat_dir="$OUTPUT_DIR/ios-sim-fat/lib"
    mkdir -p "$fat_dir"

    lipo -create \
        "$OUTPUT_DIR/ios-sim-arm64/lib/$lib_name" \
        "$OUTPUT_DIR/ios-sim-x86_64/lib/$lib_name" \
        -output "$fat_dir/$lib_name"
}

# Create fat library for macOS (arm64 + x86_64)
create_macos_fat_lib() {
    local lib_name=$1
    local fat_dir="$OUTPUT_DIR/macos-fat/lib"
    mkdir -p "$fat_dir"

    lipo -create \
        "$OUTPUT_DIR/macos-arm64/lib/$lib_name" \
        "$OUTPUT_DIR/macos-x86_64/lib/$lib_name" \
        -output "$fat_dir/$lib_name"
}

# Copy headers (same across all platforms)
copy_headers() {
    cp -R "$OUTPUT_DIR/macos-arm64/include" "$OUTPUT_DIR/macos-fat/"
    cp -R "$OUTPUT_DIR/ios-sim-arm64/include" "$OUTPUT_DIR/ios-sim-fat/"
}

# Libraries to package
LIBS=("libre.a" "librem.a" "libbaresip.a")

echo "=== Creating fat libraries ==="

for lib in "${LIBS[@]}"; do
    create_sim_fat_lib "$lib"
    create_macos_fat_lib "$lib"
done

copy_headers

echo "=== Creating XCFrameworks ==="

# libre.xcframework
xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/macos-fat/lib/libre.a" \
    -headers "$OUTPUT_DIR/macos-fat/include" \
    -library "$OUTPUT_DIR/ios-arm64/lib/libre.a" \
    -headers "$OUTPUT_DIR/ios-arm64/include" \
    -library "$OUTPUT_DIR/ios-sim-fat/lib/libre.a" \
    -headers "$OUTPUT_DIR/ios-sim-fat/include" \
    -output "$XCFW_DIR/libre.xcframework"

# librem.xcframework
xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/macos-fat/lib/librem.a" \
    -headers "$OUTPUT_DIR/macos-fat/include" \
    -library "$OUTPUT_DIR/ios-arm64/lib/librem.a" \
    -headers "$OUTPUT_DIR/ios-arm64/include" \
    -library "$OUTPUT_DIR/ios-sim-fat/lib/librem.a" \
    -headers "$OUTPUT_DIR/ios-sim-fat/include" \
    -output "$XCFW_DIR/librem.xcframework"

# libbaresip.xcframework
xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/macos-fat/lib/libbaresip.a" \
    -headers "$OUTPUT_DIR/macos-fat/include" \
    -library "$OUTPUT_DIR/ios-arm64/lib/libbaresip.a" \
    -headers "$OUTPUT_DIR/ios-arm64/include" \
    -library "$OUTPUT_DIR/ios-sim-fat/lib/libbaresip.a" \
    -headers "$OUTPUT_DIR/ios-sim-fat/include" \
    -output "$XCFW_DIR/libbaresip.xcframework"

echo "=== XCFrameworks created ==="
ls -la "$XCFW_DIR"
```

Run:

```bash
chmod +x scripts/package-xcframework.sh
./scripts/package-xcframework.sh
```

Output:

```
output/xcframeworks/
├── libre.xcframework
├── librem.xcframework
└── libbaresip.xcframework
```

---

## Xcode Integration

### 1. Add XCFrameworks to Project

1. Open your Xcode project
2. Select the project in the navigator
3. Select your app target
4. Go to **General** → **Frameworks, Libraries, and Embedded Content**
5. Click **+** → **Add Other...** → **Add Files...**
6. Select all three `.xcframework` bundles from `output/xcframeworks/`
7. Set embed option to **Do Not Embed** (static libraries)

### 2. Add OpenSSL XCFramework

If using an OpenSSL XCFramework, add it the same way. If using static `.a` files, add them via **Link Binary With Libraries** build phase.

### 3. Configure Header Search Paths

In **Build Settings** → **Header Search Paths**, add:

```
$(PROJECT_DIR)/../output/xcframeworks/libre.xcframework/*/Headers
$(PROJECT_DIR)/../output/xcframeworks/librem.xcframework/*/Headers
$(PROJECT_DIR)/../output/xcframeworks/libbaresip.xcframework/*/Headers
```

Or use a bridging header for Swift:

```c
// TonePhoneBridge.h
#include <re/re.h>
#include <rem/rem.h>
#include <baresip/baresip.h>
```

### 4. Link Required System Frameworks

Add these frameworks in **Link Binary With Libraries**:

| Framework | Purpose |
|-----------|---------|
| `AudioToolbox.framework` | Audio I/O |
| `AudioUnit.framework` | AudioUnit driver |
| `AVFoundation.framework` | iOS audio session |
| `CoreAudio.framework` | macOS audio |
| `Security.framework` | Keychain, TLS |
| `SystemConfiguration.framework` | Network reachability |
| `Network.framework` | Modern networking (optional) |

### 5. Add Linker Flags

In **Build Settings** → **Other Linker Flags**:

```
-lz
-lresolv
```

These link system libraries required by libre.

---

## Bridging Header for Swift

Create a bridging header to expose C APIs to Swift:

```c
// TonePhone-Bridging-Header.h

#ifndef TonePhone_Bridging_Header_h
#define TonePhone_Bridging_Header_h

#include <re/re.h>
#include <rem/rem.h>
#include <baresip/baresip.h>

// Include your bridge layer headers here
// #include "tp_bridge.h"

#endif
```

Set in **Build Settings** → **Objective-C Bridging Header**:

```
$(PROJECT_DIR)/TonePhone/TonePhone-Bridging-Header.h
```

---

## Apple Platform Caveats

### App Sandbox (macOS)

If App Sandbox is enabled, you need these entitlements:

```xml
<!-- TonePhone.entitlements -->
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

- `network.client` — outbound SIP/RTP connections
- `network.server` — inbound RTP (required for ICE, STUN responses)
- `audio-input` — microphone access

### Hardened Runtime (macOS)

For notarization, enable Hardened Runtime with:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### Microphone Permission (iOS + macOS)

Add to `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>TonePhone needs microphone access for voice calls.</string>
```

### iOS Audio Session

On iOS, configure the audio session before starting calls:

```swift
import AVFoundation

func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
    try session.setActive(true)
}
```

The `audiounit` module handles most of this, but you may need to activate the session at app level.

### iOS Background Audio

To continue calls in background (limited), add to `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

Note: True background VoIP on iOS requires push notifications and CallKit, which are out of scope for v1.

### Bitcode

Bitcode is deprecated as of Xcode 14. Do not enable it.

---

## Verification

After integration, verify the build:

```bash
# Check XCFramework structure
file output/xcframeworks/libbaresip.xcframework/macos-arm64_x86_64/libbaresip.a
# Should show: Mach-O universal binary with 2 architectures

# Check iOS device slice
file output/xcframeworks/libbaresip.xcframework/ios-arm64/libbaresip.a
# Should show: current ar archive

# List symbols
nm -g output/xcframeworks/libbaresip.xcframework/macos-arm64_x86_64/libbaresip.a | grep baresip_
```

Build and run the Xcode project. If linking fails, check:

1. All XCFrameworks are added to the target
2. OpenSSL is linked
3. System frameworks are linked
4. Linker flags `-lz -lresolv` are set

---

## Clean Build

To start fresh:

```bash
rm -rf build/ output/
./scripts/build-core.sh
./scripts/package-xcframework.sh
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `openssl/ssl.h` not found | Check `OPENSSL_ROOT_DIR` points to correct platform build |
| Undefined symbols for `_deflate` | Add `-lz` to linker flags |
| Undefined symbols for `_res_query` | Add `-lresolv` to linker flags |
| Architecture mismatch | Verify `CMAKE_OSX_ARCHITECTURES` matches target |
| Simulator build fails on M1 | Build both arm64 and x86_64 simulator slices |
| Code signing fails | Ensure XCFrameworks are not embedded (static libs) |

---

## References

- [baresip GitHub](https://github.com/baresip/baresip)
- [libre GitHub](https://github.com/baresip/re)
- [librem GitHub](https://github.com/baresip/rem)
- [Apple XCFramework Documentation](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
- [CMake iOS Toolchain](https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html#cross-compiling-for-ios-tvos-or-watchos)
