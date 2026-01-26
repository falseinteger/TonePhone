//
//  ActiveCallView.swift
//  TonePhone
//
//  View displayed during an active call with call controls.
//

import SwiftUI

/// View displayed during an active call.
struct ActiveCallView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showDTMFKeypad = false

    var body: some View {
        VStack(spacing: 0) {
            // Call state header
            callStateHeader
                .padding(.top, 24)

            Spacer()

            // Remote party info and duration
            VStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 80, height: 80)

                    Text(remotePartyInitials)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(.accentColor)
                }

                // Remote party name/number
                Text(remotePartyDisplay)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)

                // Call duration
                if viewModel.callState == .established || viewModel.callState == .held {
                    Text(viewModel.callDurationFormatted)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // DTMF Keypad (expandable)
            if showDTMFKeypad {
                DTMFKeypadView(onDigitPressed: { digit in
                    viewModel.sendDTMF(digit)
                })
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Call controls
            callControls
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: showDTMFKeypad)
    }

    // MARK: - Call State Header

    private var callStateHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(callStateColor)
                .frame(width: 8, height: 8)

            Text(callStateText)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var callStateColor: Color {
        switch viewModel.callState {
        case .outgoing, .early:
            return .orange
        case .incoming:
            return .blue
        case .established:
            return .green
        case .held:
            return .yellow
        case .idle, .ended:
            return .gray
        }
    }

    private var callStateText: String {
        switch viewModel.callState {
        case .idle:
            return "Idle"
        case .outgoing:
            return "Calling..."
        case .incoming:
            return "Incoming Call"
        case .early:
            return "Ringing..."
        case .established:
            return "Connected"
        case .held:
            return "On Hold"
        case .ended:
            return "Call Ended"
        }
    }

    // MARK: - Remote Party Info

    private var remotePartyDisplay: String {
        viewModel.remotePartyName ?? viewModel.remotePartyURI ?? "Unknown"
    }

    private var remotePartyInitials: String {
        let name = remotePartyDisplay
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        // For phone numbers or single words, take first 2 chars
        let filtered = name.filter { $0.isLetter || $0.isNumber }
        return String(filtered.prefix(2)).uppercased()
    }

    // MARK: - Call Controls

    private var isIncomingCall: Bool {
        if case .incoming = viewModel.callState {
            return true
        }
        return false
    }

    private var callControls: some View {
        VStack(spacing: 16) {
            if isIncomingCall {
                // Incoming call: Answer and Decline buttons
                incomingCallControls
            } else {
                // Active call: Mute, Keypad, Hold buttons
                activeCallControls
            }
        }
    }

    private var incomingCallControls: some View {
        HStack(spacing: 16) {
            // Decline button
            Button(action: {
                viewModel.hangupCall()
            }) {
                HStack {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 20))
                    Text("Decline")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Answer button
            Button(action: {
                viewModel.answerCall()
            }) {
                HStack {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 20))
                    Text("Answer")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    private var activeCallControls: some View {
        VStack(spacing: 16) {
            // Top row: Mute, Keypad, Hold
            HStack(spacing: 24) {
                // Mute button
                CallControlButton(
                    icon: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: viewModel.isMuted ? "Unmute" : "Mute",
                    isActive: viewModel.isMuted,
                    action: {
                        viewModel.toggleMute()
                    }
                )

                // Keypad button
                CallControlButton(
                    icon: "circle.grid.3x3.fill",
                    label: "Keypad",
                    isActive: showDTMFKeypad,
                    action: {
                        showDTMFKeypad.toggle()
                    }
                )

                // Hold button
                CallControlButton(
                    icon: viewModel.isOnHold ? "play.fill" : "pause.fill",
                    label: viewModel.isOnHold ? "Resume" : "Hold",
                    isActive: viewModel.isOnHold,
                    action: {
                        viewModel.toggleHold()
                    }
                )
            }

            // Hangup button
            Button(action: {
                viewModel.hangupCall()
            }) {
                HStack {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 20))
                    Text("End Call")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Call Control Button

/// Circular button for call controls (mute, hold, keypad).
private struct CallControlButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(isActive ? .white : .primary)
                }

                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DTMF Keypad

/// Grid of DTMF digit buttons.
struct DTMFKeypadView: View {
    let onDigitPressed: (String) -> Void

    private let digits: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(digits, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { digit in
                        DTMFButton(digit: digit, action: {
                            onDigitPressed(digit)
                        })
                    }
                }
            }
        }
    }
}

/// Individual DTMF digit button.
private struct DTMFButton: View {
    let digit: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(digit)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .frame(width: 64, height: 48)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Established Call") {
    ActiveCallView(viewModel: AppViewModel())
        .frame(width: 350, height: 500)
}
