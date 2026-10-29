//
//  DialpadView.swift
//  TonePhone
//
//  Telephone keypad, used for dialing and for sending tones during a call.
//

import SwiftUI

/// Telephone keypad with round keys, laid out like the Phone app.
struct KeypadView: View {
    let onKey: (String) -> Void

    private static let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"],
    ]

    private static let letters: [String: String] = [
        "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
        "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ", "0": "+",
    ]

    var body: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 12) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            onKey(key)
                        } label: {
                            VStack(spacing: -2) {
                                Text(key)
                                    .font(.system(size: key == "*" ? 30 : 26, weight: .regular))
                                Text(Self.letters[key] ?? " ")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(.quaternary))
                            .contentShape(Circle())
                        }
                        .buttonStyle(KeypadButtonStyle())
                        .accessibilityLabel(Self.accessibilityName(for: key))
                    }
                }
            }
        }
    }

    private static func accessibilityName(for key: String) -> String {
        switch key {
        case "*": return "Star"
        case "#": return "Pound"
        default: return key
        }
    }
}

/// Darkens a key while it is pressed.
private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Circle().fill(.primary.opacity(configuration.isPressed ? 0.15 : 0)))
    }
}

/// Keypad popover for dialing. Digits can also be typed on the keyboard.
struct DialKeypadPopover: View {
    @Binding var input: String
    let onCall: (String) -> Void

    @FocusState private var isFocused: Bool

    /// Shows the formatted number while storing what was typed.
    private var formattedBinding: Binding<String> {
        Binding(
            get: { PhoneNumberService.formatPartial(input) },
            set: { newValue in
                input = PhoneNumberService.looksLikeAddress(newValue)
                    ? newValue
                    : PhoneNumberService.dialableCharacters(of: newValue)
            }
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                TextField("Number", text: formattedBinding, prompt: Text("Enter Number"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 24))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit(call)

                Button {
                    if !input.isEmpty { input.removeLast() }
                } label: {
                    Label("Delete", systemImage: "delete.backward")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .opacity(input.isEmpty ? 0 : 1)
                .disabled(input.isEmpty)
                .help("Delete")
            }

            KeypadView { key in
                input.append(key)
            }

            Button(action: call) {
                Label("Call", systemImage: "phone.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.green))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(input.isEmpty)
            .help("Call")
        }
        .padding(20)
        .frame(width: 260)
        .onAppear { isFocused = true }
    }

    private func call() {
        let number = input.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return }
        input = ""
        onCall(number)
    }
}

#Preview("Keypad") {
    DialKeypadPopover(input: .constant("415")) { _ in }
}
