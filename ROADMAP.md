# Roadmap

This document tracks baresip feature parity and TonePhone implementation status.

No versions. No timelines. No promises. Just a checklist.

---

## Status Key

- `[ ]` — Not started
- `[~]` — In progress
- `[x]` — Done
- `[—]` — Will not implement / out of scope

---

## App Foundation

### Core App

- [ ] App lifecycle management (macOS)
- [ ] App lifecycle management (iOS)
- [ ] Settings storage (UserDefaults)
- [ ] Secure credential storage (Keychain)
- [ ] Call history storage (JSON)
- [ ] Log file management

### Bridge Layer

- [ ] Core initialization / shutdown
- [ ] Account CRUD operations
- [ ] Registration state callbacks
- [ ] Call control API
- [ ] Call state callbacks
- [ ] Audio device enumeration
- [ ] Diagnostics API
- [ ] Event dispatch to main thread

### Platform Adapters

- [ ] CoreAudio device selection (macOS)
- [ ] AVAudioSession management (iOS)
- [ ] Microphone permission request
- [ ] Audio route change handling
- [ ] App background/foreground handling

---

## User Interface

### macOS

- [ ] Main window layout
- [ ] Account configuration screen
- [ ] Registration status indicator
- [ ] Dialpad / URI input
- [ ] Incoming call alert
- [ ] Active call screen
- [ ] Call controls (answer, hangup, hold, mute)
- [ ] DTMF input
- [ ] Audio device picker
- [ ] Call history list
- [ ] Settings screen
- [ ] Log viewer
- [ ] Diagnostics export

### iOS

- [ ] Main screen layout
- [ ] Account configuration
- [ ] Registration status
- [ ] Dialpad
- [ ] Incoming call screen
- [ ] Active call screen
- [ ] Call controls
- [ ] DTMF
- [ ] Audio route picker
- [ ] Call history
- [ ] Settings
- [ ] Log viewer

---

## Audio Codecs

Priority codecs for TonePhone:

| Codec | Status | Notes |
|-------|--------|-------|
| g711 | [ ] | Required. PCMU/PCMA. Universal compatibility. |
| opus | [ ] | Required. Modern, efficient, good quality. |
| g722 | [ ] | Optional. Wideband, good compatibility. |

### Other Codecs (baresip supported, lower priority)

- [ ] aac — Advanced Audio Codec
- [ ] amr — AMR (mobile networks)
- [ ] aptx — aptX (Bluetooth, niche)
- [ ] codec2 — Low bitrate (ham radio, niche)
- [ ] g7221 — G.722.1 (uncommon)
- [—] g726 — Deprecated in baresip
- [ ] l16 — Uncompressed (testing only)

---

## Audio I/O

### Apple Platforms (Required)

| Module | Status | Platform |
|--------|--------|----------|
| audiounit | [ ] | macOS, iOS |
| coreaudio | [ ] | macOS (device enumeration) |

### Other Platforms (Not shipped in TonePhone)

- [—] alsa — Linux
- [—] pulse — Linux
- [—] jack — Linux/macOS (pro audio)
- [—] portaudio — Cross-platform
- [—] sndio — BSD
- [—] wasapi — Windows
- [—] winwave — Windows
- [—] opensles — Android
- [—] aaudio — Android

---

## Audio Processing

| Module | Status | Notes |
|--------|--------|-------|
| webrtc_aec | [ ] | Echo cancellation. Important for speaker use. |
| plc | [ ] | Packet loss concealment. Quality improvement. |
| augain | [ ] | Volume adjustment. May be useful. |

### Lower Priority / Specialized

- [ ] aubridge — Audio bridging
- [ ] aufile — WAV file input (testing)
- [ ] ausine — Sine wave (testing)
- [ ] mixausrc — Source mixer
- [ ] mixminus — Conferencing mixer
- [ ] sndfile — Audio recording
- [ ] vumeter — Level metering
- [—] gst — GStreamer (not on Apple)

---

## NAT Traversal

| Module | Status | Notes |
|--------|--------|-------|
| stun | [ ] | Required. Basic NAT traversal. |
| turn | [ ] | Required. Relay for symmetric NAT. |
| ice | [ ] | Required. Full ICE support. |
| natpmp | [ ] | Optional. Router port mapping. |
| pcp | [ ] | Optional. Port Control Protocol. |

---

## Security / Encryption

| Module | Status | Notes |
|--------|--------|-------|
| srtp | [ ] | Required. Media encryption (SDES). |
| dtls_srtp | [ ] | Required. Media encryption (DTLS). |
| gzrtp | [ ] | Optional. ZRTP support. Adds complexity. |

---

## Video

Video is explicitly out of scope for TonePhone.

- [—] All video codecs (av1, vp8, vp9, avcodec, h26x)
- [—] All video sources (avcapture, v4l2, dshow, etc.)
- [—] All video outputs (sdl, x11, directfb, etc.)
- [—] Video processing (selfview, snapshot, swscale, etc.)

---

## Presence / Messaging

Out of scope for TonePhone.

- [—] presence — Presence
- [—] mwi — Message waiting
- [—] contact — Contact list sync

---

## Control Interfaces

TonePhone has its own native UI. Baresip control modules are for debugging only.

| Module | Status | Notes |
|--------|--------|-------|
| debug_cmd | [ ] | Useful for development |
| ctrl_tcp | [ ] | JSON control, useful for testing |
| rtcpsummary | [ ] | RTCP stats, exposed via diagnostics |

### Not Needed

- [—] ctrl_dbus — Linux only
- [—] httpd — HTTP UI
- [—] httpreq — HTTP client
- [—] mqtt — IoT messaging
- [—] stdio — Console UI
- [—] cons — Network console
- [—] menu — Interactive menu
- [—] gtk — GTK UI
- [—] wincons — Windows console

---

## Utilities

| Module | Status | Notes |
|--------|--------|-------|
| account | [ ] | Account file loader |
| syslog | [ ] | System logging (macOS) |
| uuid | [ ] | UUID generation |

### Not Needed

- [—] echo — Echo test server
- [—] evdev — Linux input
- [—] multicast — Multicast RTP
- [—] serreg — Serial registration

---

## Future Features

These are tracked but not committed to any timeline.

### CallKit (iOS)

- [ ] Incoming call handling via CallKit
- [ ] Call directory integration
- [ ] System call UI

Requires push notification infrastructure. Significant effort.

### Push Notifications (iOS)

- [ ] VoIP push registration
- [ ] Push notification handling
- [ ] Background wake

Requires server-side infrastructure.

### Multiple Accounts

- [ ] UI for multiple accounts
- [ ] Account switching
- [ ] Per-account call history

Data model supports this. UI complexity increase.

### Menubar Mode (macOS)

- [ ] Menubar icon
- [ ] Quick dial from menubar
- [ ] Status display

Nice to have for power users.

### Call Recording

- [ ] Local call recording
- [ ] Recording indicator
- [ ] Recording storage

Legal implications vary by jurisdiction.

### Conferencing

- [ ] Multi-party calls
- [ ] Conference UI

Baresip supports this. UI is complex.

---

## Documentation

For each shipped feature:

- [ ] User-facing description
- [ ] Configuration options
- [ ] Troubleshooting tips
- [ ] Example configurations

---

## Module Shipping Policy

**Default on:** Modules that are stable, useful, and have no problematic dependencies.

**Default off:** Modules that add complexity, have niche use cases, or require user opt-in.

**Not shipped:** Modules for other platforms, deprecated modules, or out-of-scope features.

App Store builds exclude modules with dependencies that don't fit Apple guidelines.
