# UI Guidelines

TonePhone follows Apple Human Interface Guidelines (HIG) for all UI decisions. This document codifies UI/UX rules for consistent, native-feeling interfaces across macOS and iOS.

**Rule: When in doubt, follow Apple HIG. Apple defaults always win.**

---

## Core Principles

### HIG First

- UI must follow [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) for both macOS and iOS
- Prefer native system controls over custom implementations
- Visual consistency over originality
- Match platform conventions exactly

### Accessibility

Accessibility is mandatory, not optional:

- **VoiceOver:** All interactive elements must have labels
- **Keyboard navigation:** Full keyboard support on macOS
- **Dynamic Type:** Respect user font size preferences on iOS
- **Reduced Motion:** Honor system motion preferences
- **High Contrast:** Support increased contrast mode

---

## Platform Behavior

### Framework

- SwiftUI is the primary UI framework
- Shared UI state and logic must be platform-agnostic
- Platform-specific presentation lives in per-target UI layers

### macOS Expectations

- Menu bar integration with standard menus
- Keyboard-first interaction model
- Multi-window support where appropriate
- Respect system accent color
- Standard window chrome and behaviors

### iOS Expectations

- Touch-first interaction model
- Navigation stacks for drill-down flows
- System sheets for modal content
- Respect safe areas and notches
- Proper handling of multitasking

---

## Visual System

### Accent Color

- Use Apple system blue: `#007AFF`
- Do NOT define custom accent colors
- Do NOT override system tint behavior
- Let the system handle accent color inheritance

### Typography

- Use system fonts (SF Pro, SF Compact, SF Mono)
- Respect Dynamic Type on iOS
- Do NOT use custom fonts

### Colors

- Use semantic system colors (`Color.primary`, `Color.secondary`, etc.)
- Support both light and dark mode automatically
- Do NOT hardcode color values

---

## App Icon

### Master Asset

- Single master icon: 1024×1024 PNG used as the source
- Platform-specific sizes are derived from the master for iOS and macOS
- No rounded corners baked in (system applies them)
- No shadows baked in
- No effects baked in

### Content Area

- Design within ~90% of canvas for macOS-safe area
- This is visual guidance, not a separate asset
- Perceived depth comes from gradients and material, not hard shadows

### Glyphs and Iconography

- Subtle shading allowed for visual separation (Apple-style)
- Avoid heavy drop shadows
- Avoid high-contrast outlines
- Icons must remain legible at 32×32 and 16×16

---

## Component Mapping

### Required Views

| Component | Description |
|-----------|-------------|
| Dialer / Keypad | Phone number input with dial button |
| Accounts List | List of configured SIP accounts |
| Account Editor | Add/edit account details |
| Active Call | In-call controls (mute, hold, hangup, keypad) |
| Incoming Call | Call notification (window on macOS, screen on iOS) |
| Settings | App preferences and SIP configuration |

### Settings Organization

- Group advanced SIP settings together
- Hide dangerous options by default
- Use progressive disclosure
- Label technical options clearly

---

## Keyboard Shortcuts (macOS)

### Required Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+N` | New account |
| `Cmd+K` | Open dialer / dial |
| `Cmd+,` | Open settings |

### Standard Behaviors

- `Cmd+C` / `Cmd+V` for copy/paste must work
- Tab navigation must work in all forms
- Escape closes sheets and popovers
- Return/Enter confirms dialogs

---

## UX Non-Goals

What TonePhone UI is NOT:

- Not an imitation of iOS Phone.app
- No heavy animations or transitions
- No custom widgets where system controls exist
- No skeuomorphic design
- No gratuitous visual effects

---

## Review Checklist

Every UI pull request must pass:

- [ ] Uses native system controls
- [ ] Behaves like a standard macOS app
- [ ] Behaves like a standard iOS app
- [ ] Accessibility labels present on all interactive elements
- [ ] Keyboard navigation works (macOS)
- [ ] No custom UI where system UI exists
- [ ] Follows HIG color and typography guidelines
- [ ] Supports both light and dark mode

---

## References

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [SF Symbols](https://developer.apple.com/sf-symbols/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)

---

## Final Rule

If there is a conflict between:
- Personal preference
- Custom design ideas
- AI creativity
- Third-party design systems

...and Apple Human Interface Guidelines:

**Apple HIG always wins.**
