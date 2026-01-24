# CLAUDE.md

This file provides development context for AI tools.
It is optional and not part of the TonePhone product.

## Build Commands

```bash
# Build for macOS (Debug) - primary platform
xcodebuild -project TonePhone.xcodeproj -scheme TonePhone -configuration Debug

# Build for iOS Simulator (Debug)
xcodebuild -project TonePhone.xcodeproj -scheme TonePhone -sdk iphonesimulator -configuration Debug

# List schemes and targets
xcodebuild -project TonePhone.xcodeproj -list
```

No test target is configured yet.

## Architecture

Four layers with strict separation:

```
Apps (SwiftUI)           ← macOS/iOS frontends
    ↓
TonePhone Bridge         ← C API + Swift wrapper, async events
    ↓
Platform Adapters        ← audio session, permissions, lifecycle
    ↓
Baresip Core (C)         ← SIP + RTP + codecs + NAT + encryption
```

### Repository Layout

```
core/           baresip + libre (submodule/vendored), build scripts, patches
bridge/         C headers (include/), C implementation (src/), Swift wrapper (swift/)
platform/       apple/audio, apple/permissions, apple/lifecycle, apple/callkit
apps/           macOS/, iOS/
```

### Bridge Layer (C API boundary)

Swift calls a stable C API (`tp_*` functions), never baresip structs directly.

Key API groups:
- **Lifecycle:** `tp_init()`, `tp_start()`, `tp_stop()`
- **Accounts:** `tp_account_add()`, `tp_account_register()`, `tp_account_remove()`
- **Calls:** `tp_call_start()`, `tp_call_answer()`, `tp_call_hangup()`, `tp_call_hold()`, `tp_call_mute()`, `tp_call_dtmf()`
- **Events:** `tp_set_event_callback(fn, ctx)`
- **Diagnostics:** `tp_get_rtp_stats()`, `tp_get_sip_trace()`, `tp_export_logs()`

### Threading Rules

- Baresip core runs on dedicated background thread
- Bridge posts events onto a safe queue
- UI receives events on main thread
- **No direct UI calls from C. Ever.**

### Event Types (Swift)

`CoreStateChanged`, `AccountStateChanged`, `CallStateChanged`, `MediaStateChanged`, `DeviceStateChanged`, `LogLine`

## Core Rules

- One SIP engine, no duplicated SIP logic
- UI never touches SIP internals
- Logs must be human-readable
- Debugging must be easy

## Development Principles

- Prefer boring, maintainable solutions over clever ones
- Avoid overengineering
- Respect SIP edge cases
- Clean Swift ↔ C interop for baresip integration
- Simplicity over features
- No telephony jargon in UI unless necessary

## v1 Scope

**In scope:** SIP registration, audio calls, mute/hold, DTMF, call history, settings, logs/diagnostics

**Out of scope:** Video, chat, presence, provisioning, cloud sync, push notifications, CallKit (initially)

## Baresip Module Policy

See `ROADMAP.md` for full baresip feature parity checklist. Policy:
- Ship minimal set enabled by default (stable, useful)
- Everything else: off by default, advanced toggle, or "supported in core but not exposed in UI"

## Storage

No Core Data/SwiftData in v1:
- **Accounts:** JSON + Keychain for credentials
- **Call history:** JSON (ring buffer)
- **UI prefs:** UserDefaults

## Build Strategy

Build `libre` + `librem` + `libbaresip` as static libraries, package into XCFrameworks. See `BUILDING.md` for full build scripts and Xcode integration.

```bash
./scripts/build-core.sh          # Build all platforms
./scripts/package-xcframework.sh # Create XCFrameworks
```

Enabled modules: `audiounit`, `opus`, `g711`, `stun`, `turn`, `ice`, `srtp`, `dtls_srtp`, `account`

## Documentation

- `README.md` — Project overview and non-goals
- `ARCHITECTURE.md` — System design and layer responsibilities
- `BUILDING.md` — Build scripts and Xcode integration
- `ROADMAP.md` — Feature parity checklist
- `CONTRIBUTING.md` — How to contribute
- `SECURITY.md` — Vulnerability reporting
- `THIRD_PARTY_LICENSES.md` — Third-party dependency licenses

## Licensing

TonePhone code is MIT. Dependencies (baresip, libre, librem, OpenSSL, Opus) are BSD-3-Clause or Apache-2.0. All permissive, all compatible. Attribution required in binary distributions.
