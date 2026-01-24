# Contributing

TonePhone is an open-source project. Contributions are welcome.

---

## Before You Start

Read the [README](README.md) to understand what TonePhone is and isn't. Read the [ARCHITECTURE](ARCHITECTURE.md) to understand how the code is organized.

TonePhone has a specific scope. Not every feature belongs here.

---

## Ways to Contribute

### Bug Reports

Found a bug? Open an issue with:

- What you expected to happen
- What actually happened
- Steps to reproduce
- TonePhone version, macOS/iOS version
- Relevant log output (use the diagnostics export)

Do not include SIP credentials or server addresses in public issues.

### Feature Requests

Have an idea? Open an issue to discuss before implementing. Many features are intentionally out of scope. Discussing first saves everyone time.

Good feature requests:
- Solve a real problem you have
- Fit the project's scope and philosophy
- Are specific, not vague

### Code Contributions

1. Fork the repository
2. Create a branch from `main`
3. Make your changes
4. Test on macOS (primary platform)
5. Open a pull request

Small, focused PRs are easier to review than large ones.

### Documentation

Documentation improvements are always welcome:
- Typo fixes
- Clarifications
- Missing information
- Better examples

### Testing

- Test on different macOS versions
- Test on iOS devices and simulators
- Test with different SIP providers
- Report what works and what doesn't

---

## Code Style

### Swift

- Follow Apple's Swift API Design Guidelines
- Use SwiftUI idioms for UI code
- Prefer value types where appropriate
- Use `async/await` for asynchronous code
- Keep UI code in the UI layer, SIP logic in the bridge

### C (Bridge Layer)

- Follow the style of existing code
- Use `tp_` prefix for public functions
- Return error codes, not exceptions
- Document public APIs in headers
- Keep functions focused and small

### General

- No trailing whitespace
- Files end with a newline
- Use meaningful commit messages
- One logical change per commit

---

## What We're Looking For

**Welcome:**
- Bug fixes
- Performance improvements
- Code clarity improvements
- Documentation
- Test coverage
- Accessibility improvements
- Localization

**Discuss First:**
- New features
- Architectural changes
- New dependencies
- UI redesigns

**Out of Scope:**
- Video support
- Messaging / chat
- Presence / buddy lists
- Enterprise features (provisioning, LDAP, etc.)
- Cross-platform beyond Apple
- Analytics or telemetry

---

## Review Process

1. A maintainer will review your PR
2. Feedback may be given
3. Changes may be requested
4. Once approved, the PR will be merged

Be patient. This is a personal project, not a company with dedicated staff.

---

## Development Setup

1. Clone with submodules:
   ```bash
   git clone --recursive https://github.com/user/tonephone.git
   ```

2. Build core libraries:
   ```bash
   ./scripts/build-core.sh
   ./scripts/package-xcframework.sh
   ```

3. Open `apps/macOS/TonePhone.xcodeproj` in Xcode

4. Build and run

See [BUILDING.md](BUILDING.md) for detailed instructions.

---

## Testing

There is no formal test suite yet. Manual testing is expected:

- Account registration works
- Outgoing calls connect
- Incoming calls ring
- Audio flows both directions
- Hold/mute work
- DTMF works
- App doesn't crash

Test against a SIP server you control or a known-good public service.

---

## Commit Messages

Write clear commit messages:

```
Short summary (50 chars or less)

Longer description if needed. Explain what and why,
not how (the code shows how).

- Bullet points are fine
- Keep lines under 72 characters
```

Examples:
- `Fix crash when account has no password`
- `Add hold button to call screen`
- `Improve error message for TLS failures`

Not helpful:
- `Fix bug`
- `Update code`
- `WIP`

---

## Questions?

Open an issue. There's no chat server, mailing list, or Discord.
