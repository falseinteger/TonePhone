//
//  ActiveCallsListView.swift
//  TonePhone
//
//  View displaying the list of active calls (incoming, outgoing, established, held).
//

import SwiftUI

/// Represents an active call in the list.
struct ActiveCallItem: Identifiable {
    let id: CallID
    let state: UICallState
    let remoteURI: String?
    let remoteName: String?
    let duration: TimeInterval?
    let isMuted: Bool
    let isOnHold: Bool

    /// Display name for the call.
    var displayName: String {
        if let name = remoteName, !name.isEmpty {
            return name
        }
        if let uri = remoteURI {
            // Extract user part from SIP URI
            if uri.lowercased().hasPrefix("sip:") {
                let withoutScheme = String(uri.dropFirst(4))
                if let atIndex = withoutScheme.firstIndex(of: "@") {
                    return String(withoutScheme[..<atIndex])
                }
                return withoutScheme
            }
            return uri
        }
        return "Unknown"
    }

    /// Status text for the call.
    var statusText: String {
        switch state {
        case .idle:
            return "Idle"
        case .outgoing:
            return "Calling..."
        case .incoming:
            return "Incoming"
        case .early:
            return "Ringing..."
        case .established:
            if isOnHold {
                return "On Hold"
            }
            return "Connected"
        case .held:
            return "On Hold"
        case .ended:
            return "Ended"
        }
    }

    /// Whether this is an incoming call that hasn't been answered.
    var isIncomingRinging: Bool {
        if case .incoming = state {
            return true
        }
        return false
    }

    /// Whether this call can be answered.
    var canAnswer: Bool {
        isIncomingRinging
    }

    /// Whether this call can be hung up.
    var canHangup: Bool {
        switch state {
        case .idle, .ended:
            return false
        default:
            return true
        }
    }
}

/// View displaying all active calls.
struct ActiveCallsListView: View {
    @ObservedObject var viewModel: AppViewModel

    /// Get active calls from the view model.
    private var activeCalls: [ActiveCallItem] {
        // Currently we only support one active call
        // This can be extended for multiple calls in the future
        guard let callID = viewModel.activeCallID else { return [] }

        return [
            ActiveCallItem(
                id: callID,
                state: viewModel.callState,
                remoteURI: viewModel.remotePartyURI,
                remoteName: viewModel.remotePartyName,
                duration: viewModel.callDuration,
                isMuted: viewModel.isMuted,
                isOnHold: viewModel.isOnHold
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Call list
            if activeCalls.isEmpty {
                emptyState
            } else {
                callList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Active Calls")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text("\(activeCalls.count) call\(activeCalls.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: "phone.badge.checkmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("No active calls")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Call List

    private var callList: some View {
        List {
            ForEach(activeCalls) { call in
                ActiveCallRow(
                    call: call,
                    onTap: {
                        viewModel.showActiveCall()
                    },
                    onAnswer: {
                        viewModel.answerCall()
                    },
                    onHangup: {
                        viewModel.hangupCall()
                    },
                    onToggleHold: {
                        viewModel.toggleHold()
                    },
                    onToggleMute: {
                        viewModel.toggleMute()
                    }
                )
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Active Call Row

private struct ActiveCallRow: View {
    let call: ActiveCallItem
    let onTap: () -> Void
    let onAnswer: () -> Void
    let onHangup: () -> Void
    let onToggleHold: () -> Void
    let onToggleMute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Call direction/state icon
            stateIcon
                .frame(width: 32, height: 32)

            // Call info
            VStack(alignment: .leading, spacing: 2) {
                Text(call.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(call.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(statusColor)

                    if let duration = call.duration, duration > 0,
                       case .established = call.state {
                        Text(formatDuration(duration))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if call.isMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if call.canAnswer {
                    // Answer button for incoming calls
                    Button {
                        onAnswer()
                    } label: {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Answer")
                }

                if case .established = call.state {
                    // Hold button
                    Button {
                        onToggleHold()
                    } label: {
                        Image(systemName: call.isOnHold ? "play.fill" : "pause.fill")
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(call.isOnHold ? "Resume" : "Hold")

                    // Mute button
                    Button {
                        onToggleMute()
                    } label: {
                        Image(systemName: call.isMuted ? "mic.slash.fill" : "mic.fill")
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(call.isMuted ? Color.orange : Color.gray)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(call.isMuted ? "Unmute" : "Mute")
                }

                if call.canHangup {
                    // Hangup button
                    Button {
                        onHangup()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(call.canAnswer ? "Decline" : "Hang Up")
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var stateIcon: some View {
        ZStack {
            Circle()
                .fill(stateBackgroundColor)

            Image(systemName: stateIconName)
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
    }

    private var stateIconName: String {
        switch call.state {
        case .incoming:
            return "phone.arrow.down.left"
        case .outgoing, .early:
            return "phone.arrow.up.right"
        case .established:
            return call.isOnHold ? "pause.fill" : "phone.fill"
        case .held:
            return "pause.fill"
        case .ended:
            return "phone.down.fill"
        default:
            return "phone"
        }
    }

    private var stateBackgroundColor: Color {
        switch call.state {
        case .incoming:
            return .blue
        case .outgoing, .early:
            return .green
        case .established:
            return call.isOnHold ? .orange : .green
        case .held:
            return .orange
        case .ended:
            return .gray
        default:
            return .gray
        }
    }

    private var statusColor: Color {
        switch call.state {
        case .incoming:
            return .blue
        case .outgoing, .early:
            return .green
        case .established:
            return call.isOnHold ? .orange : .green
        case .held:
            return .orange
        case .ended:
            return .secondary
        default:
            return .secondary
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Preview

#Preview("Active Calls List") {
    ActiveCallsListView(viewModel: AppViewModel())
        .frame(width: 320, height: 300)
}
