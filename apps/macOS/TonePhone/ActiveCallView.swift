//
//  ActiveCallView.swift
//  TonePhone
//
//  View displayed during an active call with call controls.
//  Designed for macOS following Apple Human Interface Guidelines.
//

import SwiftUI

/// View displayed during an active call.
///
/// macOS-appropriate design with:
/// - Compact layout for desktop use
/// - Adaptive buttons (icon-only when space is limited)
/// - DTMF keypad as popover
/// - Keyboard shortcuts
struct ActiveCallView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showDTMFKeypad = false
    @State private var dtmfHistory: String = ""

    /// Minimum width to show text labels on buttons
    private let compactWidthThreshold: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < compactWidthThreshold

            VStack(spacing: 0) {
                // Main content area
                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 20)

                    // Caller info
                    callerInfoSection

                    // Call status
                    callStatusBadge

                    // DTMF history (when digits have been entered)
                    if !dtmfHistory.isEmpty {
                        dtmfHistoryView
                    }

                    Spacer()
                }

                Divider()

                // Control bar at bottom
                controlBar(isCompact: isCompact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Caller Info

    private var callerInfoSection: some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Text(remotePartyInitials)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }

            // Name
            Text(remotePartyDisplay)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            // Duration (when connected)
            if isEstablishedOrHeld {
                Text(viewModel.callDurationFormatted)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Call Status Badge

    private var callStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(callStateColor)
                .frame(width: 8, height: 8)

            Text(callStateText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - DTMF History

    private var dtmfHistoryView: some View {
        Text(dtmfHistory)
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    // MARK: - Control Bar

    private func controlBar(isCompact: Bool) -> some View {
        HStack(spacing: 0) {
            if isIncomingCall {
                incomingCallControls(isCompact: isCompact)
            } else {
                activeCallControls(isCompact: isCompact)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Incoming Call Controls

    private func incomingCallControls(isCompact: Bool) -> some View {
        HStack(spacing: 12) {
            Spacer()

            // Decline
            Button(action: { viewModel.hangupCall() }) {
                AdaptiveLabel(
                    title: "Decline",
                    systemImage: "phone.down.fill",
                    isCompact: isCompact
                )
            }
            .buttonStyle(CallButtonStyle(color: .red))
            .keyboardShortcut(.escape, modifiers: [])

            // Answer
            Button(action: { viewModel.answerCall() }) {
                AdaptiveLabel(
                    title: "Answer",
                    systemImage: "phone.fill",
                    isCompact: isCompact
                )
            }
            .buttonStyle(CallButtonStyle(color: .green))
            .keyboardShortcut(.return, modifiers: [])

            Spacer()
        }
    }

    // MARK: - Active Call Controls

    private func activeCallControls(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            // Mute
            Button(action: { viewModel.toggleMute() }) {
                AdaptiveLabel(
                    title: viewModel.isMuted ? "Unmute" : "Mute",
                    systemImage: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                    isCompact: isCompact
                )
            }
            .buttonStyle(ControlButtonStyle(isActive: viewModel.isMuted))
            .keyboardShortcut("m", modifiers: .command)
            .help("Mute microphone (⌘M)")

            // Hold
            Button(action: { viewModel.toggleHold() }) {
                AdaptiveLabel(
                    title: viewModel.isOnHold ? "Resume" : "Hold",
                    systemImage: viewModel.isOnHold ? "play.fill" : "pause.fill",
                    isCompact: isCompact
                )
            }
            .buttonStyle(ControlButtonStyle(isActive: viewModel.isOnHold))
            .keyboardShortcut("h", modifiers: .command)
            .help("Hold call (⌘H)")

            // Keypad
            Button(action: { showDTMFKeypad.toggle() }) {
                AdaptiveLabel(
                    title: "Keypad",
                    systemImage: "circle.grid.3x3.fill",
                    isCompact: isCompact
                )
            }
            .buttonStyle(ControlButtonStyle(isActive: showDTMFKeypad))
            .keyboardShortcut("k", modifiers: .command)
            .help("Show keypad (⌘K)")
            .popover(isPresented: $showDTMFKeypad, arrowEdge: .top) {
                DTMFKeypadPopover(
                    dtmfHistory: $dtmfHistory,
                    onDigitPressed: { digit in
                        dtmfHistory.append(digit)
                        viewModel.sendDTMF(digit)
                    }
                )
            }

            Spacer()

            // End Call
            Button(action: { viewModel.hangupCall() }) {
                AdaptiveLabel(
                    title: "End",
                    systemImage: "phone.down.fill",
                    isCompact: isCompact
                )
            }
            .buttonStyle(CallButtonStyle(color: .red))
            .keyboardShortcut(.escape, modifiers: [])
            .help("End call (Esc)")
        }
    }

    // MARK: - Helpers

    private var isIncomingCall: Bool {
        if case .incoming = viewModel.callState { return true }
        return false
    }

    private var isEstablishedOrHeld: Bool {
        viewModel.callState == .established || viewModel.callState == .held
    }

    private var remotePartyDisplay: String {
        viewModel.remotePartyName ?? viewModel.remotePartyURI ?? "Unknown"
    }

    private var remotePartyInitials: String {
        let name = remotePartyDisplay
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        let filtered = name.filter { $0.isLetter || $0.isNumber }
        return String(filtered.prefix(2)).uppercased()
    }

    private var callStateColor: Color {
        switch viewModel.callState {
        case .outgoing, .early: return .orange
        case .incoming, .established: return .green
        case .held: return .yellow
        case .idle, .ended: return .secondary
        }
    }

    private var callStateText: String {
        switch viewModel.callState {
        case .idle: return "Idle"
        case .outgoing: return "Calling..."
        case .incoming: return "Incoming Call"
        case .early: return "Ringing..."
        case .established: return "Connected"
        case .held: return "On Hold"
        case .ended: return "Call Ended"
        }
    }
}

// MARK: - Adaptive Label

/// Label that shows icon + text or icon-only based on available space.
private struct AdaptiveLabel: View {
    let title: String
    let systemImage: String
    let isCompact: Bool

    var body: some View {
        if isCompact {
            Image(systemName: systemImage)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - Control Button Style

/// Standard macOS-style control button.
private struct ControlButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isActive ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Call Button Style

/// Colored action button for Answer/Decline/End.
private struct CallButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - DTMF Keypad Popover

/// DTMF keypad shown as a popover.
private struct DTMFKeypadPopover: View {
    @Binding var dtmfHistory: String
    let onDigitPressed: (String) -> Void

    private let keypadData: [[KeypadKey]] = [
        [.init("1", letters: ""), .init("2", letters: "ABC"), .init("3", letters: "DEF")],
        [.init("4", letters: "GHI"), .init("5", letters: "JKL"), .init("6", letters: "MNO")],
        [.init("7", letters: "PQRS"), .init("8", letters: "TUV"), .init("9", letters: "WXYZ")],
        [.init("*", letters: ""), .init("0", letters: ""), .init("#", letters: "")]
    ]

    var body: some View {
        VStack(spacing: 12) {
            // History display
            Text(dtmfHistory.isEmpty ? "Digits" : dtmfHistory)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(dtmfHistory.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)

            // Keypad grid
            VStack(spacing: 8) {
                ForEach(keypadData, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row) { key in
                            DTMFKey(key: key, action: {
                                onDigitPressed(key.digit)
                            })
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}

/// Model for a keypad key.
private struct KeypadKey: Identifiable, Hashable {
    let id = UUID()
    let digit: String
    let letters: String

    init(_ digit: String, letters: String) {
        self.digit = digit
        self.letters = letters
    }
}

/// Individual DTMF key button.
private struct DTMFKey: View {
    let key: KeypadKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(key.digit)
                    .font(.system(size: 18, weight: .medium, design: .rounded))

                if !key.letters.isEmpty {
                    Text(key.letters)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 56, height: 44)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Active Call") {
    ActiveCallView(viewModel: AppViewModel())
        .frame(width: 320, height: 400)
}

#Preview("Compact") {
    ActiveCallView(viewModel: AppViewModel())
        .frame(width: 250, height: 400)
}
