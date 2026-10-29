//
//  DialpadView.swift
//  TonePhone
//
//  Dial field and keypad for entering phone numbers or SIP addresses.
//

import SwiftUI

/// Text field for a number, username or SIP address, with a Call button.
///
/// Phone numbers are formatted while typing (if enabled in Settings);
/// the raw digits are kept for dialing.
struct DialField: View {
    @Binding var input: String
    let onCall: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var formatVersion = 0

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shows formatted input while storing what the user typed.
    private var formattedBinding: Binding<String> {
        Binding(
            get: { _ = formatVersion; return PhoneNumberService.formatPartial(input) },
            set: { newValue in
                if PhoneNumberService.looksLikeAddress(newValue) {
                    input = newValue
                } else {
                    // Keep only characters that mean something when dialing
                    input = PhoneNumberService.dialableCharacters(of: newValue)
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Number or address", text: formattedBinding, prompt: Text("Enter a number or address"))
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($isFocused)
                .onSubmit(call)
                .labelsHidden()

            Button(action: call) {
                Label("Call", systemImage: "phone.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(trimmedInput.isEmpty)
            .help("Call (Return)")
        }
        .onAppear { isFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .phoneNumberFormatDidChange)) { _ in
            formatVersion += 1
        }
    }

    private func call() {
        guard !trimmedInput.isEmpty else { return }
        onCall(trimmedInput)
        input = ""
    }
}

/// Telephone keypad. Used for dialing and for sending tones during a call.
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
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            onKey(key)
                        } label: {
                            VStack(spacing: 0) {
                                Text(key)
                                    .font(.title2.weight(.medium))
                                Text(Self.letters[key] ?? " ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 52, height: 40)
                        }
                        .buttonStyle(.bordered)
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

/// Keypad popover for dialing: appends to the dial field; long numbers can be typed directly.
struct DialKeypadPopover: View {
    @Binding var input: String
    let onCall: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(input.isEmpty ? " " : PhoneNumberService.formatPartial(input))
                .font(.title2.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(input.isEmpty ? "No number entered" : input)

            KeypadView { key in
                input.append(key)
            }

            HStack {
                Button {
                    if !input.isEmpty { input.removeLast() }
                } label: {
                    Label("Delete", systemImage: "delete.backward")
                }
                .disabled(input.isEmpty)

                Spacer()

                Button {
                    let number = input
                    input = ""
                    onCall(number)
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.defaultAction)
                .disabled(input.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}

#Preview("Dial Field") {
    DialField(input: .constant("4155550123")) { _ in }
        .padding()
        .frame(width: 360)
}

#Preview("Keypad") {
    DialKeypadPopover(input: .constant("415")) { _ in }
}
