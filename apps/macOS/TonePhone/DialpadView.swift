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
            TextField("Enter number or address", text: $input)
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
                DialpadKey(main: "0", sub: "+", action: { append("0") }, longAction: { append("+") })
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
            .disabled(input.isEmpty)
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
            .disabled(input.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .controlSize(.large)
    }

    // MARK: - Actions

    private func append(_ char: String) {
        input.append(char)
    }

    private func initiateCall() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCall(trimmed)
    }
}

// MARK: - Dialpad Key

private struct DialpadKey: View {
    let main: String
    let sub: String?
    let action: () -> Void
    var longAction: (() -> Void)?

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
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
            .background(backgroundColor)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in longAction?() }
        )
        .accessibilityLabel(main)
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color(nsColor: .controlAccentColor).opacity(0.2)
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
    .frame(width: 280, height: 400)
}
