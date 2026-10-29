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

Today the macOS adapters live in the app target (`apps/macOS/TonePhone`):
`IncomingCallManager` (notifications, ringtone, Dock attention), microphone
permission handling in `AppViewModel`, and CoreAudio device enumeration in
`bridge/src/tp_audio.c`. A separate `platform/` directory will be split out
when the iOS app needs to share them.

`tp_audio.c` also registers the `vpio` audio driver that calls use by
default. It runs one Voice Processing I/O unit for both playback and
recording, which gives echo cancellation and noise reduction (baresip's
audiounit module opens two separate units, so the voice processing unit
there cannot see what it plays). It also opens the selected input and output
devices; audiounit always uses the system defaults. With echo cancellation
turned off in Settings, calls use audiounit; ringtones always do.

### TonePhone Bridge

The critical boundary between C and Swift. A stable C API that:

- Hides baresip internals from Swift code
- Provides a clean, versioned interface
- Handles threading: every call into baresip runs inside
  `re_thread_enter()`/`re_thread_leave()`; events are posted to the main queue
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
│   ├── re/                    # libre (git submodule, upstream tag; includes librem)
│   ├── baresip/               # baresip (git submodule, upstream tag)
│   ├── patches/               # TonePhone patches applied to baresip at build time
│   ├── openssl/               # OpenSSL builds per platform (generated)
│   └── opus/                  # Opus builds per platform (generated)
│
├── bridge/
│   ├── include/tp_bridge.h    # Public C API
│   ├── src/                   # tp_core, tp_account, tp_call, tp_events, tp_audio, tp_log
│   └── swift/TonePhoneCore.swift  # Swift wrapper and event publisher
│
├── apps/
│   └── macOS/TonePhone/       # macOS app (SwiftUI); an iOS app is planned
│       ├── App/               # entry point, menus, view model, logging
│       ├── Accounts/          # account storage, list and editor
│       ├── Calls/             # call window, recents, keypad, number formatting
│       ├── Logs/              # log viewer and export
│       └── Settings/          # settings window and store
│
├── scripts/
│   ├── build-openssl.sh, build-opus.sh, build-core.sh
│   ├── package-xcframework.sh
│   └── dev-sip-server.py      # Local SIP server for testing
│
└── docs/screenshots/          # README images
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
tp_error_t tp_call_get_stats(tp_call_id_t id, tp_call_stats_t *out);
```

### Events

```c
typedef void (*tp_event_callback_t)(const tp_event_t *event, void *ctx);
void tp_set_event_callback(tp_event_callback_t callback, void *ctx);
```

### Diagnostics

```c
tp_error_t tp_log_init(const char *log_dir);
tp_error_t tp_log_set_level(tp_log_level_t level);
tp_error_t tp_log_get_path(char *buf, size_t size);
tp_error_t tp_log_flush(void);
void tp_log_message(tp_log_level_t level, const char *message);  /* app messages */
tp_error_t tp_log_set_sip_trace(bool enabled);   /* credentials redacted */
```

`tp_call_get_stats()` returns a call's codec, packet counts, bitrates and,
once RTCP reports arrive, loss, jitter and round-trip time. When a call ends
the bridge writes the same numbers to the log as one line. The app exports
the log file itself.

### Design Principles

- Functions return error codes, not exceptions
- Output parameters for created IDs
- Opaque handles (IDs) instead of pointers
- All strings are UTF-8, null-terminated
- Thread-safe for calls from any thread; baresip is entered under the libre lock (lock order: re lock, then the bridge mutex)

---

## Event Model

Baresip is event-driven. TonePhone exposes a single event stream to the app layer.

### Event Types

```swift
enum TonePhoneEvent {
    case coreStateChanged(CoreState)
    case accountStateChanged(AccountID, AccountState)
    case callStateChanged(CallID, CallState, CallEventDetails)  // remote name, owning account
    case mediaChanged(CallID, audioEstablished: Bool, videoEstablished: Bool, encrypted: Bool)
    case audioDeviceChanged
    case messageWaiting(AccountID, VoicemailStatus)   // RFC 3842 message-summary
}
```

### Threading

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Baresip   │────▶│   Bridge    │────▶│     UI      │
│   Thread    │     │   Queue     │     │ Main Thread │
└─────────────┘     └─────────────┘     └─────────────┘
```

1. Baresip core runs `re_main` on a dedicated background thread
2. Bridge calls from Swift take the libre lock (`re_thread_enter`) before touching baresip
3. baresip events reach the bridge callback on the SIP thread; the Swift wrapper copies the data
4. The wrapper re-posts each event with `DispatchQueue.main.async`, which keeps them in order

**Rule: No direct UI calls from C code. Ever.**

### Swift Integration

```swift
// In the app
TonePhoneCore.shared.events          // already delivered on the main thread
    .sink { event in
        switch event {
        case .callStateChanged(let id, let state, _):
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
├── config                # baresip configuration, rewritten on every launch
├── accounts.json         # Account list (no secrets)
├── call_history.json     # Call history (per account, newest 100)
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

- Log viewer window (Window › Logs) with level and SIP-message filters, search, pause
- Copy selected entries; export the log file
- Toggle SIP message tracing
- Call statistics (codec, packets, loss, jitter, round trip) in the call window when diagnostics are on

### Diagnostics Bundle (planned)

A future one-step export will create a zip containing:

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
- Echo cancellation and noise reduction (Voice Processing I/O)
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
