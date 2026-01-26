# Architecture

TonePhone is a macOS-first SIP client built on top of baresip. This document describes the system architecture, integration strategy, and design decisions.

---

## Overview

```
┌─────────────────────────────────────┐
│           Apps (SwiftUI)            │
│         macOS  /  iOS               │
├─────────────────────────────────────┤
│         TonePhone Bridge            │
│      C API  +  Swift Wrapper        │
├─────────────────────────────────────┤
│        Platform Adapters            │
│   Audio / Permissions / Lifecycle   │
├─────────────────────────────────────┤
│        Baresip Core (C)             │
│   SIP / RTP / Codecs / NAT / TLS    │
└─────────────────────────────────────┘
```

Four layers with strict separation of concerns.

---

## Layer Responsibilities

### Baresip Core

The foundation. Handles all SIP and media complexity:

- SIP signaling (registration, calls, transfers)
- RTP media transport
- Audio codecs (Opus, G.711)
- NAT traversal (STUN, TURN, ICE)
- Encryption (SRTP, DTLS-SRTP)
- Configuration and account management

This layer is pure C. No UI code, no platform-specific code.

**Audio-Only Design:** TonePhone intentionally excludes video support. The baresip build includes only audio modules to minimize binary size and complexity. See [BUILDING.md](BUILDING.md#modules-and-features) for the full module list.

### Platform Adapters

Thin adapters that connect baresip to Apple platform APIs:

| Adapter | macOS | iOS |
|---------|-------|-----|
| Audio I/O | CoreAudio | AVAudioSession |
| Permissions | System Preferences | Settings app |
| App Lifecycle | NSApplication | UIApplication |
| Background | N/A | Background modes |
| CallKit | N/A | Future |

Adapters are minimal. They translate between platform APIs and what baresip expects.

### TonePhone Bridge

The critical boundary between C and Swift. A stable C API that:

- Hides baresip internals from Swift code
- Provides a clean, versioned interface
- Handles threading (events posted to main queue)
- Converts C data structures to Swift-friendly types

Swift never imports baresip headers directly. All interaction goes through the bridge.

### Apps

Native UI for each platform:

- **macOS**: SwiftUI with AppKit where needed
- **iOS**: SwiftUI

Apps are thin. They display state, accept input, and call bridge APIs. No SIP logic lives here.

**UI Rules:** All UI code must follow [UI_GUIDELINES.md](UI_GUIDELINES.md). Apple Human Interface Guidelines take precedence over custom design ideas. Use native system controls wherever possible.

---

## Repository Layout

```
tonephone/
├── core/
│   ├── re/                    # libre (git submodule)
│   ├── rem/                   # librem (git submodule)
│   ├── baresip/               # baresip (git submodule)
│   ├── openssl/               # OpenSSL builds per platform
│   └── patches/               # Patches to upstream (if any)
│
├── bridge/
│   ├── include/               # Public C headers
│   │   └── tp_bridge.h
│   ├── src/                   # C implementation
│   │   ├── tp_core.c
│   │   ├── tp_account.c
│   │   ├── tp_call.c
│   │   └── tp_events.c
│   └── swift/                 # Swift wrapper
│       ├── TonePhoneCore.swift
│       ├── Account.swift
│       ├── Call.swift
│       └── Events.swift
│
├── platform/
│   └── apple/
│       ├── audio/             # AudioUnit / AVAudioSession
│       ├── permissions/       # Microphone, contacts
│       └── lifecycle/         # App state handling
│
├── apps/
│   ├── macOS/                 # macOS app target
│   └── iOS/                   # iOS app target
│
├── scripts/
│   ├── build-core.sh
│   └── package-xcframework.sh
│
└── docs/
    ├── ARCHITECTURE.md
    ├── BUILDING.md
    └── ROADMAP.md
```

---

## Bridge API

The bridge exposes a C API with the `tp_` prefix. Swift calls these functions through a wrapper that provides Swift-native types and async/await support.

### Lifecycle

```c
tp_error_t tp_init(const char *config_path, const char *log_path);
tp_error_t tp_start(void);
tp_error_t tp_stop(void);
void tp_shutdown(void);
```

### Accounts

```c
tp_error_t tp_account_add(const tp_account_config_t *config, tp_account_id_t *out_id);
tp_error_t tp_account_remove(tp_account_id_t id);
tp_error_t tp_account_register(tp_account_id_t id);
tp_error_t tp_account_unregister(tp_account_id_t id);
tp_error_t tp_account_set_default(tp_account_id_t id);
```

### Calls

```c
tp_error_t tp_call_start(const char *uri, tp_call_id_t *out_id);
tp_error_t tp_call_answer(tp_call_id_t id);
tp_error_t tp_call_hangup(tp_call_id_t id);
tp_error_t tp_call_hold(tp_call_id_t id, bool hold);
tp_error_t tp_call_mute(tp_call_id_t id, bool mute);
tp_error_t tp_call_send_dtmf(tp_call_id_t id, const char *digits);
```

### Events

```c
typedef void (*tp_event_callback_t)(const tp_event_t *event, void *ctx);
void tp_set_event_callback(tp_event_callback_t callback, void *ctx);
```

### Diagnostics

```c
tp_error_t tp_get_call_stats(tp_call_id_t id, tp_call_stats_t *out_stats);
tp_error_t tp_set_sip_trace(bool enabled);
tp_error_t tp_export_logs(const char *path);
```

### Design Principles

- Functions return error codes, not exceptions
- Output parameters for created IDs
- Opaque handles (IDs) instead of pointers
- All strings are UTF-8, null-terminated
- Thread-safe for calls from main thread

---

## Event Model

Baresip is event-driven. TonePhone exposes a single event stream to the app layer.

### Event Types

```swift
enum TonePhoneEvent {
    case coreStateChanged(CoreState)
    case accountStateChanged(AccountID, AccountState)
    case callStateChanged(CallID, CallState)
    case callMediaChanged(CallID, MediaInfo)
    case audioDeviceChanged(DeviceInfo)
    case logMessage(LogLevel, String)
}
```

### Threading

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Baresip   │────▶│   Bridge    │────▶│     UI      │
│   Thread    │     │   Queue     │     │ Main Thread │
└─────────────┘     └─────────────┘     └─────────────┘
```

1. Baresip core runs on a dedicated background thread
2. Events are captured by bridge callbacks
3. Bridge posts events to a serial queue
4. Swift wrapper delivers events on main thread

**Rule: No direct UI calls from C code. Ever.**

### Swift Integration

```swift
// In the app
TonePhoneCore.shared.events
    .receive(on: DispatchQueue.main)
    .sink { event in
        switch event {
        case .callStateChanged(let id, let state):
            updateCallUI(id: id, state: state)
        // ...
        }
    }
```

---

## Configuration

TonePhone manages a minimal subset of baresip configuration.

### Philosophy

- Sane defaults out of the box
- Expose only settings users actually need
- Hide complexity behind "Advanced" toggle
- Never require manual config file editing

### Storage

| Data | Storage | Notes |
|------|---------|-------|
| Accounts | JSON + Keychain | Credentials in Keychain |
| Call History | JSON | Ring buffer, local only |
| Settings | UserDefaults | App preferences |
| Logs | Files | Rotated, exportable |

No Core Data. No CloudKit. No sync.

### Config Files

Under the app container:

```
~/Library/Application Support/TonePhone/
├── config                # baresip configuration file
├── accounts.json         # Account list (no secrets)
├── history.json          # Call history (future)
└── logs/
    ├── tonephone.log     # Current log file
    ├── tonephone.log.1   # Rotated logs (up to .3)
    └── ...
```

---

## Logging and Diagnostics

Logging is a first-class feature, not an afterthought.

### Log Levels

| Level | Usage |
|-------|-------|
| Error | Something broke |
| Warning | Something unexpected |
| Info | Significant events (calls, registration) |
| Debug | Detailed flow (development) |
| Trace | Wire-level detail (SIP messages) |

### File Logging

Logs are written to files in `~/Library/Application Support/TonePhone/logs/`:

```text
logs/
├── tonephone.log       # Current log file
├── tonephone.log.1     # Previous log (after rotation)
├── tonephone.log.2     # Older log
└── tonephone.log.3     # Oldest kept log
```

**Log rotation:** Files are rotated when they exceed 5 MB. Up to 3 rotated files are kept.

**Format:** Each line includes timestamp, level, and message:
```text
2024-01-25 14:32:01 [INFO ] tp_core: initialized successfully
2024-01-25 14:32:01 [DEBUG] tp_account: registering account 1
```

**Security:** Passwords and credentials are never logged, even at debug/trace level.

### In-App Features

- Log viewer with filtering
- Copy log to clipboard
- Export diagnostics bundle
- Toggle SIP trace
- View call statistics (codec, jitter, loss)

### Diagnostics Bundle

One-tap export creates a zip containing:

- Sanitized logs (credentials redacted)
- App version and build info
- System info (OS version, hardware)
- Current configuration (secrets redacted)
- Recent call statistics

---

## Platform-Specific Notes

### macOS (Primary)

- CoreAudio for audio device access
- Full audio device selection UI
- Menubar mode planned for later
- Multiple window support not prioritized
- Hardened Runtime required for notarization
- App Sandbox with network + microphone entitlements

### iOS (Secondary)

- AVAudioSession for audio routing
- Audio route selection (speaker, earpiece, Bluetooth)
- Background audio mode for active calls
- No true background without push + CallKit
- CallKit integration planned for later, not v1
- Foreground-focused client initially

### Shared Code

The bridge layer and all SIP logic is shared. Platform differences are isolated to:

- Audio adapter implementation
- Permission request flows
- App lifecycle handling
- UI implementation

---

## Security Considerations

### Credentials

- SIP passwords stored in Keychain, never in plain files
- Credentials never logged, even at trace level
- Memory cleared after use where practical

### Network

- TLS for SIP signaling (when server supports)
- SRTP/DTLS-SRTP for media encryption
- Certificate validation enabled by default
- No custom CA support in v1 (use system trust store)

### Privacy

- No analytics
- No telemetry
- No crash reporting without explicit opt-in
- All data stored locally
- No cloud features

---

## Future Considerations

Architectural decisions that anticipate future features without implementing them:

### CallKit (iOS)

Bridge API designed to support CallKit's call directory and incoming call handling. Not implemented in v1.

### Multiple Accounts

Data model supports multiple accounts. UI initially shows only default account.

### Call Recording

Audio pipeline can be extended to support recording. Not implemented, may have legal implications.

### Conferencing

Baresip supports conferencing. Bridge API can be extended. Not in scope for v1.
