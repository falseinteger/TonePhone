//
//  ActiveCallView.swift
//  TonePhone
//
//  The call window: incoming call, call in progress, and other calls.
//

import AppKit
import SwiftUI

/// Opens and closes the call window from non-view code.
///
/// The window appears when a call starts and closes when the last call
/// ends; the main window is left as it was.
@MainActor
enum CallWindow {
    static let id = "call"

    private static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == id }
    }

    static func show() {
        if let window, window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.orderFrontRegardless()
        } else {
            MainWindow.open(id: id)
        }
    }

    static func close() {
        window?.close()
    }
}

/// Content of the call window: the incoming call while it rings, the call
/// controls once it is connecting or connected.
struct ActiveCallView: View {
    @ObservedObject var viewModel: AppViewModel

    private var isIncoming: Bool {
        if case .incoming = viewModel.callState { return true }
        return false
    }

    /// Other calls: ringing (call waiting) or on hold.
    private var otherCalls: [AppViewModel.CallInfo] {
        viewModel.activeCalls.values
            .filter { call in
                guard call.id != viewModel.activeCallID else { return false }
                if case .ended = call.state { return false }
                return call.state != .idle
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(otherCalls, id: \.id) { call in
                OtherCallRow(call: call, viewModel: viewModel)
                Divider()
            }

            if viewModel.activeCallID == nil {
                Text("No Calls")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isIncoming {
                IncomingCallView(viewModel: viewModel)
            } else {
                InCallView(viewModel: viewModel)
            }
        }
        .frame(width: 300, height: 460 + CGFloat(otherCalls.count) * 52)
        .navigationTitle(viewModel.remotePartyLabels.title)
    }
}

// MARK: - Caller Avatar

/// Circle with the caller's initials, or a person symbol for numbers,
/// like Contacts monograms.
struct CallerAvatar: View {
    let title: String
    let size: CGFloat

    private var initials: String? {
        guard title.contains(where: { $0.isLetter }) else { return nil }
        let words = title.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.linearGradient(
                    // Blue-gray like Contacts monograms
                    colors: [Color(red: 0.65, green: 0.68, blue: 0.76), Color(red: 0.51, green: 0.54, blue: 0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            if let initials {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
                    .offset(y: size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Name, number and status in the middle of the call window.
private struct CallerHeader: View {
    let title: String
    let subtitle: String?
    let status: String

    var body: some View {
        VStack(spacing: 6) {
            CallerAvatar(title: title, size: 88)
                .padding(.bottom, 6)

            Text(title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(status)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Incoming Call

/// A ringing call with Decline and Accept.
///
/// Return accepts and Escape declines. When another call is connected,
/// accepting puts it on hold.
struct IncomingCallView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var isAcceptFocused: Bool

    private var labels: (title: String, subtitle: String?) { viewModel.remotePartyLabels }

    private var hasOtherConnectedCall: Bool {
        viewModel.activeCalls.values.contains {
            $0.id != viewModel.activeCallID && ($0.state == .established || $0.state == .held)
        }
    }

    private var accountName: String? {
        guard let id = viewModel.activeCallID,
              let owner = viewModel.activeCalls[id]?.ownerAccountID else { return nil }
        return viewModel.accounts.first { $0.id == owner }?.title
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            CallerHeader(
                title: labels.title,
                subtitle: labels.subtitle,
                status: accountName.map { "Incoming Call · \($0)" } ?? "Incoming Call"
            )

            if hasOtherConnectedCall {
                Text("Accepting puts your current call on hold.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 20)

            HStack(spacing: 56) {
                CircleActionButton(title: "Decline", systemImage: "phone.down.fill", tint: .red, size: 60) {
                    viewModel.hangupCall()
                }
                .keyboardShortcut(.cancelAction)
                .help("Decline (Esc)")

                CircleActionButton(title: "Accept", systemImage: "phone.fill", tint: .green, size: 60, focus: $isAcceptFocused) {
                    viewModel.answerCall()
                }
                .keyboardShortcut(.defaultAction)
                .help("Accept (Return)")
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // With keyboard navigation on, Space should accept rather than decline
        .onAppear { isAcceptFocused = true }
    }
}

// MARK: - In Call

/// A call that is connecting or connected: status, controls, End.
struct InCallView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showKeypad = false
    @State private var dtmfHistory = ""

    private var labels: (title: String, subtitle: String?) { viewModel.remotePartyLabels }

    private var isConnected: Bool {
        viewModel.callState == .established || viewModel.callState == .held
    }

    private var hasEnded: Bool {
        if case .ended = viewModel.callState { return true }
        return false
    }

    private var isEncrypted: Bool {
        guard let id = viewModel.activeCallID else { return false }
        return viewModel.activeCalls[id]?.isEncrypted ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            CallerHeader(title: labels.title, subtitle: labels.subtitle, status: statusText)

            Group {
                if !dtmfHistory.isEmpty {
                    Text(dtmfHistory)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .accessibilityLabel("Keys sent: \(dtmfHistory)")
                } else if isConnected {
                    encryptionLabel
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)

            Spacer(minLength: 16)

            controls
                .disabled(hasEnded)
                .padding(.bottom, 22)

            CircleActionButton(title: "End", systemImage: "phone.down.fill", tint: .red, size: 60) {
                viewModel.hangupCall()
            }
            .disabled(hasEnded)
            .help("End Call (⌘D)")
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.activeCallID) { _ in
            dtmfHistory = ""
            showKeypad = false
        }
    }

    /// Shows whether the audio is encrypted. Unencrypted calls are only
    /// pointed out when the account asks for encryption.
    @ViewBuilder
    private var encryptionLabel: some View {
        if isEncrypted {
            Label("Encrypted", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("The call audio is encrypted (SRTP).")
        } else if let account = viewModel.activeAccount, account.mediaEncryption != .none {
            Label("Not Encrypted", systemImage: "lock.open.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .help("The other side didn’t agree to encrypt the call audio.")
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            CircleActionButton(
                title: "Mute",
                systemImage: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                tint: nil,
                isOn: viewModel.isMuted
            ) {
                viewModel.toggleMute()
            }
            .disabled(!isConnected)
            .help("Mute (⇧⌘M)")

            CircleActionButton(title: "Keypad", systemImage: "circle.grid.3x3.fill", tint: nil, isOn: showKeypad) {
                showKeypad.toggle()
            }
            .keyboardShortcut("k")
            .help("Keypad (⌘K)")
            .popover(isPresented: $showKeypad, arrowEdge: .bottom) {
                KeypadView { key in
                    dtmfHistory.append(key)
                    viewModel.sendDTMF(key)
                }
                .padding(20)
            }

            AudioDeviceMenu(viewModel: viewModel)

            CircleActionButton(
                title: "Hold",
                systemImage: "pause.fill",
                tint: nil,
                isOn: viewModel.isOnHold
            ) {
                viewModel.toggleHold()
            }
            .disabled(!isConnected)
            .help("Hold (⇧⌘H)")
        }
    }

    private var statusText: String {
        switch viewModel.callState {
        case .idle: return " "
        case .outgoing: return "Calling…"
        case .incoming: return "Incoming Call"
        case .early: return "Ringing…"
        case .established: return viewModel.callDurationFormatted
        case .held: return "On Hold · \(viewModel.callDurationFormatted)"
        case .ended(let reason): return Self.endedText(reason)
        }
    }

    /// "Call Ended", or the reason when the call failed (e.g. "Busy").
    private static func endedText(_ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return "Call Ended" }
        let lowered = reason.lowercased()
        if lowered.contains("486") || lowered.contains("busy") { return "Busy" }
        if lowered.contains("404") || lowered.contains("not found") { return "Number Not Found" }
        if lowered.contains("480") || lowered.contains("unavailable") { return "Unavailable" }
        if lowered.contains("603") || lowered.contains("decline") { return "Declined" }
        if lowered.contains("408") || lowered.contains("timeout") { return "No Answer" }
        if lowered.contains("488") || lowered.contains("not acceptable") { return "Call Not Supported" }
        if lowered.contains("403") || lowered.contains("forbidden") { return "Call Not Allowed" }
        return "Call Ended"
    }
}

// MARK: - Other Calls

/// Another call at the top of the window: a waiting call to accept, or a
/// held call to switch to.
private struct OtherCallRow: View {
    let call: AppViewModel.CallInfo
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            CallerAvatar(title: call.labels.title, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(call.labels.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            actions
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(.bar)
    }

    private var status: String {
        switch call.state {
        case .incoming: return "Incoming Call"
        case .held: return "On Hold"
        case .established where call.isOnHold: return "On Hold"
        case .outgoing, .early: return "Calling…"
        default: return "In Call"
        }
    }

    @ViewBuilder
    private var actions: some View {
        if call.isIncomingRinging {
            Button {
                viewModel.declineCall(call.id)
            } label: {
                Image(systemName: "phone.down.fill")
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.red))
            }
            .buttonStyle(.plain)
            .help("Decline")
            .accessibilityLabel("Decline")

            Menu("Accept") {
                Button("Hold & Accept") { viewModel.answerCall(call.id) }
                Button("End & Accept") { viewModel.endAndAnswerCall(call.id) }
            } primaryAction: {
                viewModel.answerCall(call.id)
            }
            .fixedSize()
            .help("Accept and hold the current call")
        } else {
            Button("Swap") {
                viewModel.switchToCall(call.id)
            }
            .help("Hold the current call and resume this one")
        }
    }
}

// MARK: - Preview

#Preview("Call") {
    ActiveCallView(viewModel: AppViewModel.shared)
}
