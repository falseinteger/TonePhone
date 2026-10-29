# BUILDING.md — TonePhone Core Libraries

This document describes how to build **baresip** and **libre (re)** (which includes librem) as static libraries for Apple platforms, package them into XCFrameworks, and integrate them into Xcode projects.

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
│   ├── patches/               # TonePhone patches applied to baresip at build time
│   ├── baresip/               # baresip source (git submodule)
│   ├── openssl/               # OpenSSL builds per platform (created by build)
│   └── opus/                  # Opus builds per platform (optional, created by build)
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
│   ├── build-opus.sh          # Opus codec build helper (optional)
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

TonePhone builds baresip with a minimal, **audio-only** module set. Video support is intentionally excluded to reduce binary size and complexity.

### Enabled Modules

| Category | Modules | Purpose |
|----------|---------|---------|
| Audio I/O | `audiounit` | macOS/iOS native audio via AudioUnit |
| Audio Codecs | `g711` | Basic codec (PCMU/PCMA), always supported |
| Audio Codecs | `opus` | High-quality codec (optional, see below) |
| NAT Traversal | `stun` | STUN client for NAT discovery |
| NAT Traversal | `turn` | TURN relay for symmetric NAT |
| NAT Traversal | `ice` | ICE connectivity checks |
| Security | `srtp` | Secure RTP media encryption |
| Security | `dtls_srtp` | DTLS key exchange for SRTP |
| Network | `netroam` | Re-registers when the network changes |
| Voicemail | `mwi` | Message waiting indication (new voicemail) |
| Account | `account` | SIP account management |

**Note:** The `opus` module is only enabled if libopus is built. See [Opus Setup](#opus-setup-optional) below.

### Excluded Modules (Not Built)

TonePhone explicitly excludes the following module categories:

| Category | Examples | Reason |
|----------|----------|--------|
| Video codecs | `vp8`, `vp9`, `av1`, `avcodec` | Audio-only app |
| Video I/O | `v4l2`, `avcapture`, `dshow`, `fakevideo` | Audio-only app |
| Video display | `sdl`, `x11`, `directfb`, `selfview` | Audio-only app |
| Video utilities | `vidbridge`, `vidinfo`, `snapshot`, `swscale` | Audio-only app |
| Other audio drivers | `alsa`, `pulse`, `jack`, `portaudio`, `coreaudio` | Using `audiounit` |
| Android audio | `aaudio`, `opensles` | Not targeting Android |
| Windows audio | `wasapi` | Not targeting Windows |
| UI/Console | `stdio`, `cons`, `menu`, `gtk`, `wincons` | App provides UI |
| Messaging | `presence`, `contact` | Not in v1 scope |
| Debug | `debug_cmd` | Not needed in release |

### Binary Size

By building only the required modules, the resulting libraries are significantly smaller:

```text
libbaresip.a  ~600 KB  (audio-only)
libre.a       ~1.1 MB  (includes librem)
```

A full baresip build with video modules would be 3-5x larger.

### Module Configuration

Module selection is controlled in two places:

1. **Build time** (`scripts/build-core.sh`): The `BARESIP_MODULES_BASE` variable specifies which modules to compile into the static library.

2. **Runtime** (config file): The generated config file in `~/Library/Application Support/TonePhone/config` lists modules to load at startup. For statically linked modules, the `.so` extension is optional.

Example runtime config:
```text
module g711.so
module opus.so
module audiounit.so
module stun.so
module turn.so
module ice.so
module srtp.so
module dtls_srtp.so
module account.so
```

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

## Opus Setup (Optional)

The Opus codec provides high-quality audio compression for VoIP. Building libopus is **optional** — if not present, baresip will be built with G.711 only.

### Using the Build Script (Recommended)

```bash
./scripts/build-opus.sh
```

This downloads Opus 1.5.2, verifies the checksum, and builds static libraries for all platforms.

Output structure:

```text
core/opus/
├── macos-arm64/
│   ├── include/opus/
│   └── lib/libopus.a
├── macos-x86_64/
│   └── ...
├── ios-arm64/
│   └── ...
├── ios-sim-arm64/
│   └── ...
└── ios-sim-x86_64/
    └── ...
```

### Verification

After building, `build-core.sh` will automatically detect libopus and enable the `opus` module:

```bash
./scripts/build-core.sh
# Should show: "Opus codec: ENABLED (libopus found)"
```

---

## Build Strategy

`scripts/build-core.sh` builds libre and baresip as static libraries for each
platform, then `scripts/package-xcframework.sh` combines them into
XCFrameworks in `output/xcframeworks/`. The scripts are the source of truth;
read them for exact CMake flags.

### Target Matrix

| Platform | SDK | Architectures |
|----------|-----|---------------|
| macOS | macosx | arm64, x86_64 (fat) |
| iOS device | iphoneos | arm64 |
| iOS Simulator | iphonesimulator | arm64, x86_64 (fat) |

### Build Order

1. **libre (re)** — includes librem (`USE_REM=ON`); there is no separate rem build.
2. **baresip** — built from `build/src/baresip`, a copy of `core/baresip` with
   `core/patches/baresip/*.patch` applied (see [core/patches/README.md](core/patches/README.md)).

### Commands

```bash
./scripts/build-openssl.sh            # once
./scripts/build-opus.sh               # once; the macOS app links libopus
./scripts/build-core.sh --clean       # libre + baresip for all platforms
./scripts/package-xcframework.sh      # output/xcframeworks/*.xcframework
```

`build-core.sh` skips platforms whose libraries already exist; pass `--clean`
after changing submodule versions or patches.

### Updating baresip and libre

baresip and libre are released together with the same version number.
Check out the same tag in both submodules, rebuild with `--clean`, and fix
or drop patches that no longer apply. Current version: **4.12.0**.

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
$(PROJECT_DIR)/../output/xcframeworks/libbaresip.xcframework/*/Headers
```

Or use a bridging header for Swift:

```c
// TonePhoneBridge.h
#include <re/re.h>
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
