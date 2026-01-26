//
//  DialpadView.swift
//  TonePhone
//
//  Dialpad view for entering phone numbers or SIP URIs.
//

import SwiftUI

/// Dialpad view for entering phone numbers or SIP URIs to make calls.
///
/// Follows macOS Human Interface Guidelines with keyboard-first interaction,
/// proper typography, and native control styling.
struct DialpadView: View {
    /// Callback when the user initiates a call.
    let onCall: (String) -> Void

    /// The current input value.
    @State private var input = ""

    /// Whether the input field is focused.
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Display area
            displayArea
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Keypad
            keypadGrid
                .padding(16)

            Spacer(minLength: 0)

            // Call button
            callButton
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Display Area

    private var displayArea: some View {
        VStack(spacing: 4) {
            // Number display
            HStack(spacing: 0) {
                Text(input.isEmpty ? "Enter number" : input)
                    .font(.system(size: 28, weight: .light, design: .default))
                    .foregroundColor(input.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(input.isEmpty ? "No number entered" : input)

                // Backspace button
                if !input.isEmpty {
                    Button {
                        deleteLastCharacter()
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Delete (⌫)")
                    .accessibilityLabel("Delete last character")
                }
            }
            .frame(height: 40)

            // Hidden text field for keyboard input
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onSubmit {
                    initiateCall()
                }
        }
    }

    // MARK: - Keypad Grid

    private var keypadGrid: some View {
        let spacing: CGFloat = 8

        return VStack(spacing: spacing) {
            ForEach(keypadRows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.digit) { key in
                        DialpadKey(
                            digit: key.digit,
                            letters: key.letters,
                            action: { appendDigit(key.digit) },
                            longPressAction: key.longPressDigit.map { digit in
                                { appendDigit(digit) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var keypadRows: [[KeyData]] {
        [
            [KeyData("1", nil), KeyData("2", "ABC"), KeyData("3", "DEF")],
            [KeyData("4", "GHI"), KeyData("5", "JKL"), KeyData("6", "MNO")],
            [KeyData("7", "PQRS"), KeyData("8", "TUV"), KeyData("9", "WXYZ")],
            [KeyData("*", nil), KeyData("0", "+", longPress: "+"), KeyData("#", nil)]
        ]
    }

    // MARK: - Call Button

    private var callButton: some View {
        Button {
            initiateCall()
        } label: {
            Label("Call", systemImage: "phone.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(CallButtonStyle(isEnabled: !input.isEmpty))
        .disabled(input.isEmpty)
        .keyboardShortcut(.return, modifiers: [])
        .help("Call (Return)")
        .accessibilityLabel("Call")
        .accessibilityHint(input.isEmpty ? "Enter a number first" : "Call \(input)")
    }

    // MARK: - Actions

    private func appendDigit(_ digit: String) {
        input.append(digit)
    }

    private func deleteLastCharacter() {
        guard !input.isEmpty else { return }
        input.removeLast()
    }

    private func initiateCall() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCall(trimmed)
    }
}

// MARK: - Key Data

private struct KeyData: Hashable {
    let digit: String
    let letters: String?
    let longPressDigit: String?

    init(_ digit: String, _ letters: String?, longPress: String? = nil) {
        self.digit = digit
        self.letters = letters
        self.longPressDigit = longPress
    }
}

// MARK: - Dialpad Key

private struct DialpadKey: View {
    let digit: String
    let letters: String?
    let action: () -> Void
    let longPressAction: (() -> Void)?

    @State private var isHovered = false
    @State private var isPressed = false

    init(digit: String, letters: String?, action: @escaping () -> Void, longPressAction: (() -> Void)? = nil) {
        self.digit = digit
        self.letters = letters
        self.action = action
        self.longPressAction = longPressAction
    }

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 2) {
                Text(digit)
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .foregroundColor(.primary)

                if let letters = letters {
                    Text(letters)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.tertiaryLabel)
                        .tracking(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    longPressAction?()
                }
        )
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(longPressAction != nil ? "Hold to enter \(letters ?? "")" : "")
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color(nsColor: .controlAccentColor).opacity(0.15)
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.8)
        } else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.4)
        }
    }

    private var accessibilityLabelText: String {
        if let letters = letters, digit != "*" && digit != "#" {
            return "\(digit), \(letters)"
        }
        return digit
    }
}

// MARK: - Tertiary Label Color

private extension Color {
    static var tertiaryLabel: Color {
        Color(nsColor: .tertiaryLabelColor)
    }
}

// MARK: - Call Button Style

private struct CallButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color.green.opacity(0.4)
        } else if isPressed {
            return Color.green.opacity(0.8)
        } else {
            return Color.green
        }
    }
}

// MARK: - Preview

#Preview("Dialpad") {
    DialpadView { uri in
        print("Call: \(uri)")
    }
    .frame(width: 300, height: 420)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Dialpad - With Number") {
    DialpadView { uri in
        print("Call: \(uri)")
    }
    .frame(width: 300, height: 420)
    .background(Color(nsColor: .windowBackgroundColor))
}
