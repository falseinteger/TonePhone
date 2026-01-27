//
//  ActiveCallsListView.swift
//  TonePhone
//
//  View displaying the list of active calls.
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
    let isOutgoing: Bool

    /// Display name for the call.
    var displayName: String {
        if let name = remoteName, !name.isEmpty {
            return name
        }
        if let uri = remoteURI {
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
            return "Incoming Call"
        case .early:
            return "Ringing..."
        case .established:
            if isOnHold {
                return "On Hold"
            }
            return formatDuration(duration)
        case .held:
            return "On Hold"
        case .ended:
            return "Ended"
        }
    }

    var isIncomingRinging: Bool {
        if case .incoming = state { return true }
        return false
    }

    var canAnswer: Bool { isIncomingRinging }

    var canHangup: Bool {
        switch state {
        case .idle, .ended: return false
        default: return true
        }
    }

    var isActive: Bool {
        if case .established = state, !isOnHold { return true }
        return false
    }

    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration = duration, duration > 0 else { return "Connected" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// View displaying all active calls.
struct ActiveCallsListView: View {
    @ObservedObject var viewModel: AppViewModel

    private var activeCallItems: [ActiveCallItem] {
        viewModel.activeCalls.values
            .filter { callInfo in
                if case .ended = callInfo.state { return false }
                if case .idle = callInfo.state { return false }
                return true
            }
            .map { callInfo in
                ActiveCallItem(
                    id: callInfo.id,
                    state: callInfo.state,
                    remoteURI: callInfo.remoteURI,
                    remoteName: callInfo.remoteName,
                    duration: callInfo.startTime.map { Date().timeIntervalSince($0) },
                    isMuted: callInfo.isMuted,
                    isOnHold: callInfo.isOnHold,
                    isOutgoing: callInfo.isOutgoing
                )
            }
            .sorted { call1, call2 in
                func priority(_ state: UICallState) -> Int {
                    switch state {
                    case .incoming: return 0
                    case .outgoing: return 1
                    case .early: return 2
                    case .established: return 3
                    case .held: return 4
                    default: return 5
                    }
                }
                return priority(call1.state) < priority(call2.state)
            }
    }

    var body: some View {
        Group {
            if activeCallItems.isEmpty {
                emptyStateView
            } else {
                callListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "phone")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("No Active Calls")
                    .font(.headline)

                Text("Use the dialpad to make a call")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Call List

    private var callListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(activeCallItems) { call in
                    VStack(spacing: 0) {
                        CallRowView(
                            call: call,
                            isSelected: viewModel.activeCallID == call.id,
                            onSelect: { viewModel.selectCall(call.id) },
                            onAnswer: {
                                viewModel.setTargetCall(call.id)
                                viewModel.answerCall()
                            },
                            onHangup: {
                                viewModel.setTargetCall(call.id)
                                viewModel.hangupCall()
                            },
                            onToggleHold: {
                                viewModel.setTargetCall(call.id)
                                viewModel.toggleHold()
                            },
                            onToggleMute: {
                                viewModel.setTargetCall(call.id)
                                viewModel.toggleMute()
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if call.id != activeCallItems.last?.id {
                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Call Row View

private struct CallRowView: View {
    let call: ActiveCallItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onAnswer: () -> Void
    let onHangup: () -> Void
    let onToggleHold: () -> Void
    let onToggleMute: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIndicator

            // Call info
            VStack(alignment: .leading, spacing: 2) {
                Text(call.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(call.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if call.isMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Action buttons
            // Always visible for incoming and established calls, hover for others
            if shouldShowButtons {
                actionButtons
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
                .padding(.horizontal, -6)
                .padding(.vertical, -2)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Image(systemName: statusIcon)
            .font(.system(size: 18))
            .foregroundColor(statusColor)
            .frame(width: 24, height: 24)
    }

    private var statusIcon: String {
        switch call.state {
        case .incoming:
            return "phone.arrow.down.left"
        case .outgoing, .early:
            return "phone.arrow.up.right"
        case .established, .held:
            if call.isOnHold {
                return "pause.circle"
            }
            // Show direction even when established
            return call.isOutgoing ? "phone.arrow.up.right" : "phone.arrow.down.left"
        default:
            return "phone"
        }
    }

    private var statusColor: Color {
        switch call.state {
        case .incoming:
            return .blue
        case .outgoing, .early:
            return .secondary
        case .established:
            return call.isOnHold ? .orange : .green
        case .held:
            return .orange
        default:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        if isHovered {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.3)
        }
        return .clear
    }

    /// Whether to show action buttons
    private var shouldShowButtons: Bool {
        // Always show for incoming calls
        if call.isIncomingRinging { return true }
        // Always show for established calls (active or on hold)
        if case .established = call.state { return true }
        // Always show for held calls
        if case .held = call.state { return true }
        // Show on hover for other states (outgoing, early)
        return isHovered
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if call.canAnswer {
                Button {
                    onAnswer()
                } label: {
                    Text("Answer")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button {
                    onHangup()
                } label: {
                    Text("Decline")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)

            } else if case .established = call.state, !call.isOnHold {
                // Active call (not on hold)
                Button {
                    onToggleHold()
                } label: {
                    Label("Hold", systemImage: "pause.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onToggleMute()
                } label: {
                    Image(systemName: call.isMuted ? "mic.slash.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)
                .tint(call.isMuted ? .orange : nil)
                .controlSize(.small)
                .help(call.isMuted ? "Unmute" : "Mute")

                Button {
                    onHangup()
                } label: {
                    Label("End", systemImage: "phone.down.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)

            } else if case .held = call.state, true {
                // Call on hold - show Resume and End
                Button {
                    onToggleHold()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onHangup()
                } label: {
                    Label("End", systemImage: "phone.down.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)

            } else if case .established = call.state, call.isOnHold {
                // Established but on hold (alternative state)
                Button {
                    onToggleHold()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onHangup()
                } label: {
                    Label("End", systemImage: "phone.down.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)

            } else if call.canHangup {
                Button {
                    onHangup()
                } label: {
                    Label("End", systemImage: "phone.down.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Preview

#Preview("Active Calls List") {
    ActiveCallsListView(viewModel: AppViewModel())
        .frame(width: 320, height: 300)
}

#Preview("Empty State") {
    ActiveCallsListView(viewModel: AppViewModel())
        .frame(width: 320, height: 200)
}
