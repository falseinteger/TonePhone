# TonePhone

A minimal, native SIP client for macOS and iOS.

---

## What It Is

TonePhone is a SIP softphone built on [baresip](https://github.com/baresip/baresip). It provides a clean, native UI for making and receiving voice calls over SIP.

macOS is the primary platform. iOS shares the same core.

## Who It's For

- Telecom engineers who need a reliable SIP client for daily use
- Developers working with SIP infrastructure
- Technical users who want a simple, predictable phone app
- Anyone tired of bloated VoIP clients

## What Problem It Solves

There is no modern, minimal, reliable SIP client for macOS with a clean UI. Existing options are legacy-heavy, UX-hostile, or over-engineered for enterprise use cases.

TonePhone aims to be:
- Simple to use
- Predictable in behavior
- Easy to debug (logs and diagnostics are first-class)
- Respectful of your time and attention

## Project Status

**Early development.** Core architecture is defined, build system is in place, UI is in progress.

The project is usable for development and testing. Not yet ready for general use.

## Architecture

```
┌─────────────────────────────────────┐
│           Apps (SwiftUI)            │  ← macOS / iOS frontends
├─────────────────────────────────────┤
│         TonePhone Bridge            │  ← C API + Swift wrapper
├─────────────────────────────────────┤
│        Platform Adapters            │  ← Audio, permissions, lifecycle
├─────────────────────────────────────┤
│        Baresip Core (C)             │  ← SIP, RTP, codecs, NAT
└─────────────────────────────────────┘
```

Key principle: **UI never touches SIP internals directly.**

The bridge layer exposes a stable C API (`tp_*` functions) that Swift calls. Events flow asynchronously from core to UI.

See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Building

Requirements:
- macOS 14+
- Xcode 15+
- CMake, Ninja, pkg-config (via Homebrew)

Quick start:
```bash
git clone --recursive https://github.com/user/tonephone.git
cd tonephone
./scripts/build-core.sh
./scripts/package-xcframework.sh
```

See [BUILDING.md](BUILDING.md) for complete instructions.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening issues or pull requests.

## Non-Goals

TonePhone is intentionally limited. The following are explicitly out of scope:

- **Video calls** — This is an audio-only client
- **Instant messaging / chat** — Use a messaging app
- **Presence / buddy lists** — Not a social platform
- **Enterprise features** — No provisioning, no LDAP, no BLF arrays
- **Cloud sync** — Local-only by design
- **Support for every SIP provider** — Works with standards-compliant servers
- **Cross-platform beyond Apple** — macOS and iOS only
- **Maximum feature count** — Simplicity is a feature

## License

TonePhone source code is licensed under [MIT](LICENSE).

Third-party dependencies (baresip, libre, librem, OpenSSL, Opus) are licensed under BSD-3-Clause or Apache-2.0. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for details.

## Related

- [baresip](https://github.com/baresip/baresip) — The SIP engine (BSD-3-Clause)
- [libre](https://github.com/baresip/re) — baresip's core library (BSD-3-Clause)
- [librem](https://github.com/baresip/rem) — baresip's media library (BSD-3-Clause)
