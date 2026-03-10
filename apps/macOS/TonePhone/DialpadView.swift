//
//  DialpadView.swift
//  TonePhone
//
//  Dialpad view for entering phone numbers or SIP URIs.
//

import SwiftUI

/// Dialpad view for entering phone numbers or SIP URIs to make calls.
///
/// Native macOS design following Human Interface Guidelines.
struct DialpadView: View {
    /// Callback when the user initiates a call.
    let onCall: (String) -> Void

    /// The current input value.
    @State private var input = ""

    /// Whether the input field is focused.
    @FocusState private var isInputFocused: Bool

    /// Trimmed input for validation.
    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Binding that displays formatted input while storing raw dial characters.
    private var formattedBinding: Binding<String> {
        Binding(
            get: { PhoneNumberService.formatPartial(input) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                // Preserve SIP URIs and address input as-is
                if trimmed.lowercased().hasPrefix("sip:") ||
                    trimmed.lowercased().hasPrefix("sips:") ||
                    trimmed.contains("@") ||
                    trimmed.contains(where: { $0.isLetter }) {
                    input = newValue
                } else {
                    // Extract only dial-valid characters from phone-like input
                    input = String(newValue.filter { "0123456789+*#".contains($0) })
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            // Input field - native macOS text field style
            inputField
                .padding(.horizontal, 24)

            // Keypad grid
            keypadGrid
                .padding(.horizontal, 24)

            Spacer(minLength: 8)

            // Action buttons
            actionButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Input Field

    private var inputField: some View {
        HStack(spacing: 4) {
            TextField("Enter number or address", text: formattedBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .focused($isInputFocused)
                .onSubmit { initiateCall() }
                .accessibilityLabel("Phone number or SIP address")

            if !input.isEmpty {
                Button {
                    if !input.isEmpty { input.removeLast() }
                } label: {
                    Image(systemName: "delete.backward")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: [])
                .help("Delete")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Keypad

    private var keypadGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                DialpadKey(main: "1", sub: nil, action: { append("1") })
                DialpadKey(main: "2", sub: "ABC", action: { append("2") })
                DialpadKey(main: "3", sub: "DEF", action: { append("3") })
            }
            HStack(spacing: 12) {
                DialpadKey(main: "4", sub: "GHI", action: { append("4") })
                DialpadKey(main: "5", sub: "JKL", action: { append("5") })
                DialpadKey(main: "6", sub: "MNO", action: { append("6") })
            }
            HStack(spacing: 12) {
                DialpadKey(main: "7", sub: "PQRS", action: { append("7") })
                DialpadKey(main: "8", sub: "TUV", action: { append("8") })
                DialpadKey(main: "9", sub: "WXYZ", action: { append("9") })
            }
            HStack(spacing: 12) {
                DialpadKey(main: "*", sub: nil, action: { append("*") })
                DialpadKey(main: "0", sub: "+", action: { append("0") }, longPressChar: "+", longAction: { append("+") })
                DialpadKey(main: "#", sub: nil, action: { append("#") })
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Clear button
            Button("Clear") {
                input = ""
            }
            .buttonStyle(.bordered)
            .disabled(trimmedInput.isEmpty)
            .keyboardShortcut(.escape, modifiers: [])

            // Call button
            Button {
                initiateCall()
            } label: {
                Label("Call", systemImage: "phone.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(trimmedInput.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint(trimmedInput.isEmpty ? "Enter a number first" : "Call \(trimmedInput)")
        }
        .controlSize(.large)
    }

    // MARK: - Actions

    private func append(_ char: String) {
        input.append(char)
    }

    private func initiateCall() {
        guard !trimmedInput.isEmpty else { return }
        onCall(trimmedInput)
    }
}

// MARK: - Dialpad Key

private struct DialpadKey: View {
    let main: String
    let sub: String?
    let action: () -> Void
    var longPressChar: String?
    var longAction: (() -> Void)?

    @State private var isHovered = false
    @State private var isLongPressed = false

    var body: some View {
        Button {
            // Don't fire tap if long press just occurred
            if !isLongPressed {
                action()
            }
        } label: {
            VStack(spacing: 1) {
                Text(main)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)

                if let sub = sub {
                    Text(sub)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isHovered ? Color(nsColor: .controlColor) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(DialpadKeyButtonStyle())
        .onHover { isHovered = $0 }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    isLongPressed = true
                    longAction?()
                    // Reset after a short delay so next tap works
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isLongPressed = false
                    }
                }
        )
        .accessibilityLabel(main)
        .accessibilityHint(longPressChar.map { "Hold to enter \($0)" } ?? "")
    }
}

// MARK: - Dialpad Key Button Style

private struct DialpadKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Preview

#Preview("Dialpad") {
    DialpadView { uri in
        print("Call: \(uri)")
    }
    .frame(width: 280, height: 400)
}
