# Development Setup

Step-by-step instructions for setting up a TonePhone development environment from scratch.

---

## Prerequisites

### System Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| macOS | 14.0 (Sonoma) or later | Build host |
| Xcode | 15.0 or later | Install from App Store |

### Command Line Tools

Verify Xcode command line tools are installed:

```bash
xcode-select -p
# Should print: /Applications/Xcode.app/Contents/Developer
```

If not installed:

```bash
xcode-select --install
```

### Homebrew Packages

Install required build tools:

```bash
brew install cmake ninja pkg-config
```

Verify versions:

```bash
cmake --version   # 3.20+
ninja --version   # 1.11+
pkg-config --version  # 0.29+
```

---

## Setup Steps

### 1. Clone the Repository

```bash
git clone --recursive https://github.com/falseinteger/TonePhone.git
cd TonePhone
```

The `--recursive` flag clones the git submodules (baresip, libre, librem).

If you forgot `--recursive`:

```bash
git submodule update --init --recursive
```

### 2. Build OpenSSL

TonePhone requires OpenSSL for TLS and SRTP. Apple platforms don't ship OpenSSL headers, so we build it ourselves.

```bash
./scripts/build-openssl.sh
```

This downloads OpenSSL 3.4.1, verifies the checksum, and builds static libraries for all platforms (macOS arm64/x86_64, iOS device/simulator).

**Expected output:**

```text
=== Building OpenSSL 3.4.1 ===
Downloading...
Verifying checksum...
Building for macos-arm64...
Building for macos-x86_64...
...
=== OpenSSL build complete ===
```

**Time:** ~5-10 minutes on Apple Silicon

### 3. Build Core Libraries

Build baresip and its dependencies (libre, librem):

```bash
./scripts/build-core.sh
```

This builds static libraries for all platforms using CMake and Ninja.

**Expected output:**

```text
=== Building libre for macos-arm64 (arm64) ===
...
=== Building baresip for macos-arm64 (arm64) ===
...
=== Build complete ===
```

**Time:** ~3-5 minutes on Apple Silicon

### 4. Package XCFrameworks

Combine the built libraries into XCFrameworks for Xcode:

```bash
./scripts/package-xcframework.sh
```

**Expected output:**

```text
=== Creating fat libraries ===
=== Creating XCFrameworks ===
...
output/xcframeworks/
├── libre.xcframework
└── libbaresip.xcframework
```

### 5. Open Xcode Project

```bash
open apps/macOS/TonePhone.xcodeproj
```

Or open manually from Finder.

### 6. Build and Run

1. Select the **TonePhone** scheme in the toolbar
2. Select **My Mac** as the destination
3. Press **⌘R** to build and run

---

## Verification

### Check Build Artifacts

After running all scripts, verify the output:

```bash
# XCFrameworks exist
ls output/xcframeworks/
# Should show: libbaresip.xcframework  libre.xcframework

# Libraries are universal (arm64 + x86_64)
file output/macos-fat/lib/libbaresip.a
# Should show: Mach-O universal binary with 2 architectures
```

### Check Xcode Build

In Xcode:

1. Build succeeds without errors (⌘B)
2. App launches without crashes (⌘R)
3. Console shows baresip initialization logs

### Test Basic Functionality

1. App window appears
2. Can add an account (Settings > Accounts)
3. Account registers successfully (green status)

---

## Common Issues

### "openssl/ssl.h not found"

OpenSSL wasn't built or is missing for the target platform.

**Fix:** Re-run `./scripts/build-openssl.sh`

### "No such module 'TonePhoneCore'"

XCFrameworks aren't properly linked.

**Fix:**
1. Ensure `./scripts/package-xcframework.sh` completed successfully
2. In Xcode, clean build folder (⌘⇧K)
3. Rebuild (⌘B)

### Undefined symbols for `_deflate` or `_res_query`

System libraries not linked.

**Fix:** Verify linker flags in Xcode:
- Build Settings > Other Linker Flags should include `-lz -lresolv`

### Submodule directories are empty

Git submodules weren't cloned.

**Fix:**

```bash
git submodule update --init --recursive
```

### Build script fails with permission denied

Script isn't executable.

**Fix:**

```bash
chmod +x scripts/*.sh
```

### Architecture mismatch on Apple Silicon

Mixing arm64 and x86_64 binaries.

**Fix:** Clean and rebuild everything:

```bash
rm -rf build/ output/
./scripts/build-openssl.sh
./scripts/build-core.sh
./scripts/package-xcframework.sh
```

### Xcode shows "missing package" errors

The project doesn't use Swift Package Manager. Ignore or dismiss.

---

## Clean Build

To start completely fresh:

```bash
rm -rf build/ output/
./scripts/build-openssl.sh
./scripts/build-core.sh
./scripts/package-xcframework.sh
```

---

## Next Steps

- Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the codebase structure
- Read [BUILDING.md](BUILDING.md) for detailed build system documentation
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines
- Read [UI_GUIDELINES.md](UI_GUIDELINES.md) for UI development standards

---

## Getting Help

If you're stuck:

1. Check the [Common Issues](#common-issues) section above
2. Search existing [GitHub Issues](https://github.com/falseinteger/TonePhone/issues)
3. Open a new issue with:
   - macOS version
   - Xcode version
   - Full error message
   - Steps you followed
