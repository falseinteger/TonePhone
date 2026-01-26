//
//  DialpadView.swift
//  TonePhone
//
//  Dialpad view for entering phone numbers or SIP URIs.
//

import SwiftUI

/// Dialpad view for entering phone numbers or SIP URIs to make calls.
///
/// Follows macOS Human Interface Guidelines with keyboard-first interaction.
struct DialpadView: View {
    /// Callback when the user initiates a call.
    let onCall: (String) -> Void

    /// The current input value.
    @State private var input = ""

    /// Whether the input field is focused.
    @FocusState private var isInputFocused: Bool

    /// Threshold for compact layout.
    private let compactThreshold: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < compactThreshold

            VStack(spacing: 12) {
                Spacer(minLength: 8)

                // Input field
                inputField

                // Keypad
                keypad(isCompact: isCompact)

                Spacer(minLength: 8)

                // Call button
                callButton(isCompact: isCompact)
            }
            .padding(.horizontal, isCompact ? 12 : 16)
            .padding(.vertical, 12)
        }
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Input Field

    private var inputField: some View {
        HStack(spacing: 8) {
            TextField("Enter number or SIP URI", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($isInputFocused)
                .onSubmit {
                    initiateCall()
                }
                .accessibilityLabel("Phone number or SIP URI")
                .accessibilityHint("Enter a number or SIP address to call")

            if !input.isEmpty {
                Button {
                    input = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear input")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Keypad

    private func keypad(isCompact: Bool) -> some View {
        let keySize: CGFloat = isCompact ? 48 : 56
        let spacing: CGFloat = isCompact ? 6 : 8

        return VStack(spacing: spacing) {
            // Row 1: 1 2 3
            HStack(spacing: spacing) {
                DialpadKey(digit: "1", letters: nil, size: keySize, action: { appendDigit("1") })
                DialpadKey(digit: "2", letters: "ABC", size: keySize, action: { appendDigit("2") })
                DialpadKey(digit: "3", letters: "DEF", size: keySize, action: { appendDigit("3") })
            }

            // Row 2: 4 5 6
            HStack(spacing: spacing) {
                DialpadKey(digit: "4", letters: "GHI", size: keySize, action: { appendDigit("4") })
                DialpadKey(digit: "5", letters: "JKL", size: keySize, action: { appendDigit("5") })
                DialpadKey(digit: "6", letters: "MNO", size: keySize, action: { appendDigit("6") })
            }

            // Row 3: 7 8 9
            HStack(spacing: spacing) {
                DialpadKey(digit: "7", letters: "PQRS", size: keySize, action: { appendDigit("7") })
                DialpadKey(digit: "8", letters: "TUV", size: keySize, action: { appendDigit("8") })
                DialpadKey(digit: "9", letters: "WXYZ", size: keySize, action: { appendDigit("9") })
            }

            // Row 4: * 0 #
            HStack(spacing: spacing) {
                DialpadKey(digit: "*", letters: nil, size: keySize, action: { appendDigit("*") })
                DialpadKey(digit: "0", letters: "+", size: keySize, action: { appendDigit("0") }, longPressAction: { appendDigit("+") })
                DialpadKey(digit: "#", letters: nil, size: keySize, action: { appendDigit("#") })
            }
        }
    }

    // MARK: - Call Button

    private func callButton(isCompact: Bool) -> some View {
        Button {
            initiateCall()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill")
                if !isCompact {
                    Text("Call")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(input.isEmpty ? Color.green.opacity(0.5) : Color.green)
            )
        }
        .buttonStyle(.plain)
        .disabled(input.isEmpty)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityLabel("Call")
        .accessibilityHint(input.isEmpty ? "Enter a number first" : "Call \(input)")
    }

    // MARK: - Actions

    private func appendDigit(_ digit: String) {
        input.append(digit)
    }

    private func deleteLastDigit() {
        if !input.isEmpty {
            input.removeLast()
        }
    }

    private func initiateCall() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCall(trimmed)
    }
}

// MARK: - Dialpad Key

private struct DialpadKey: View {
    let digit: String
    let letters: String?
    let size: CGFloat
    let action: () -> Void
    var longPressAction: (() -> Void)?

    @State private var isHovered = false
    @State private var isPressed = false

    init(digit: String, letters: String?, size: CGFloat, action: @escaping () -> Void, longPressAction: (() -> Void)? = nil) {
        self.digit = digit
        self.letters = letters
        self.size = size
        self.action = action
        self.longPressAction = longPressAction
    }

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 1) {
                Text(digit)
                    .font(.system(size: size * 0.4, weight: .medium, design: .rounded))

                if let letters = letters {
                    Text(letters)
                        .font(.system(size: size * 0.14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    longPressAction?()
                }
        )
        .accessibilityLabel(digit)
        .accessibilityHint(letters.map { "Also represents \($0)" } ?? "")
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color(nsColor: .controlAccentColor).opacity(0.3)
        } else if isHovered {
            return Color(nsColor: .controlColor)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }
}

// MARK: - Preview

#Preview("Dialpad") {
    DialpadView { uri in
        print("Call: \(uri)")
    }
    .frame(width: 300, height: 400)
}

#Preview("Compact") {
    DialpadView { uri in
        print("Call: \(uri)")
    }
    .frame(width: 220, height: 380)
}
