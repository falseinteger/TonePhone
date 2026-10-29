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

- [x] App lifecycle management (macOS)
- [ ] App lifecycle management (iOS)
- [x] Settings storage (UserDefaults)
- [x] Secure credential storage (Keychain)
- [x] Call history storage (JSON)
- [x] Log file management

### Bridge Layer

- [x] Core initialization / shutdown
- [x] Account CRUD operations
- [x] Registration state callbacks
- [x] Call control API
- [x] Call state callbacks
- [x] Audio device enumeration
- [~] Diagnostics API (log file, SIP message trace; RTP statistics not yet)
- [x] Event dispatch to main thread

### Platform Adapters

- [x] CoreAudio device selection (macOS)
- [ ] AVAudioSession management (iOS)
- [x] Microphone permission request
- [x] Audio route change handling (device hot-plug)
- [x] App background/foreground handling (wake from sleep, network change)

---

## User Interface

### macOS

- [x] Main window layout
- [x] Account configuration screen
- [x] Registration status indicator
- [x] Dialpad / URI input
- [x] Incoming call alert
- [x] Active call screen
- [x] Call controls (answer, hangup, hold, mute)
- [x] DTMF input
- [x] Audio device picker
- [x] Call history list
- [x] Settings screen
- [x] Log viewer
- [x] Diagnostics export
- [x] Voicemail (number per account, new-message indicator)
- [x] Call encryption indicator

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
| g711 | [x] | Required. PCMU/PCMA. Universal compatibility. |
| opus | [x] | Required. Modern, efficient, good quality. |
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
| audiounit | [x] | macOS, iOS |
| coreaudio | [x] | macOS (device enumeration) |

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
| stun | [x] | Required. Basic NAT traversal. |
| turn | [x] | Required. Relay for symmetric NAT. |
| ice | [x] | Required. Full ICE support. |
| natpmp | [ ] | Optional. Router port mapping. |
| pcp | [ ] | Optional. Port Control Protocol. |
| netroam | [x] | Re-registers when the network changes. |

---

## Security / Encryption

| Module | Status | Notes |
|--------|--------|-------|
| srtp | [x] | Required. Media encryption (SDES). |
| dtls_srtp | [x] | Required. Media encryption (DTLS). |
| TLS trust | [x] | System certificates plus an imported CA file. |
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

Chat and presence are out of scope. Voicemail notifications are in.

- [x] mwi — Message waiting (voicemail indicator)
- [—] presence — Presence
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
| account | [x] | Account file loader |
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

- [~] UI for multiple accounts (one connected at a time)
- [x] Account switching
- [x] Per-account call history

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
