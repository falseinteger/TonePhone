//
//  ActiveCallView.swift
//  TonePhone
//
//  Incoming call screen and in-call screen.
//

import SwiftUI

/// Shows the displayed call: the incoming call screen while it rings,
/// the in-call screen once it is connecting or connected.
struct ActiveCallView: View {
    @ObservedObject var viewModel: AppViewModel

    private var isIncoming: Bool {
        if case .incoming = viewModel.callState { return true }
        return false
    }

    var body: some View {
        Group {
            if isIncoming {
                IncomingCallView(viewModel: viewModel)
            } else {
                InCallView(viewModel: viewModel)
            }
        }
        .navigationTitle(viewModel.remotePartyLabels.title)
        .navigationSubtitle(viewModel.activeAccount.map { "on \($0.title)" } ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.goBackToCallsList()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to recents and calls (⌘[)")
            }
        }
    }
}

// MARK: - Caller Avatar

/// Circle with the caller's initials, or a person symbol for numbers.
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
                    colors: [Color(nsColor: .systemGray), Color(nsColor: .darkGray)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            if let initials {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Incoming Call

/// Full-window screen for a ringing call with Answer and Decline.
///
/// Return answers and Escape declines. When another call is connected,
/// answering puts it on hold.
struct IncomingCallView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var labels: (title: String, subtitle: String?) { viewModel.remotePartyLabels }

    private var hasOtherConnectedCall: Bool {
        viewModel.activeCalls.values.contains {
            $0.id != viewModel.activeCallID && ($0.state == .established || $0.state == .held)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZStack {
                if !reduceMotion {
                    Circle()
                        .stroke(Color.green.opacity(0.35), lineWidth: 2)
                        .frame(width: 112, height: 112)
                        .scaleEffect(isPulsing ? 1.25 : 1)
                        .opacity(isPulsing ? 0 : 1)
                        .accessibilityHidden(true)
                }
                CallerAvatar(title: labels.title, size: 104)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }

            VStack(spacing: 6) {
                Text(labels.title)
                    .font(.title.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                if let subtitle = labels.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text(incomingDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)

            if hasOtherConnectedCall {
                Label("Answering puts your current call on hold.", systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }

            Spacer(minLength: 24)

            HStack(spacing: 40) {
                CallActionButton(
                    title: "Decline",
                    systemImage: "phone.down.fill",
                    tint: .red
                ) {
                    viewModel.hangupCall()
                }
                .keyboardShortcut(.cancelAction)
                .help("Decline (Esc)")

                CallActionButton(
                    title: "Answer",
                    systemImage: "phone.fill",
                    tint: .green
                ) {
                    viewModel.answerCall()
                }
                .keyboardShortcut(.defaultAction)
                .help("Answer (Return)")
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var incomingDescription: String {
        "Incoming Call"
    }
}

/// Large round call button with a caption, used for Answer, Decline and End.
struct CallActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(tint))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - In Call

/// Screen for a call that is connecting or connected.
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

    /// Other calls ringing while this one is in progress.
    private var waitingCalls: [AppViewModel.CallInfo] {
        viewModel.activeCalls.values
            .filter { $0.id != viewModel.activeCallID && $0.isIncomingRinging }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(waitingCalls, id: \.id) { call in
                CallWaitingBanner(call: call, viewModel: viewModel)
            }

            Spacer(minLength: 16)

            CallerAvatar(title: labels.title, size: 80)

            VStack(spacing: 4) {
                Text(labels.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                if let subtitle = labels.subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text(statusText)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                if isConnected {
                    encryptionLabel
                }

                if !dtmfHistory.isEmpty {
                    Text(dtmfHistory)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .accessibilityLabel("Keys sent: \(dtmfHistory)")
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 16)

            controls
                .disabled(hasEnded)
                .padding(.bottom, 16)

            CallActionButton(title: "End", systemImage: "phone.down.fill", tint: .red) {
                viewModel.hangupCall()
            }
            .disabled(hasEnded)
            .help("End Call (⌘D)")
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.activeCallID) { _ in
            dtmfHistory = ""
            showKeypad = false
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { viewModel.isMuted }, set: { _ in viewModel.toggleMute() })) {
                Label(viewModel.isMuted ? "Unmute" : "Mute", systemImage: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .help("Mute (⌘U)")
            .disabled(!isConnected)

            Toggle(isOn: Binding(get: { viewModel.isOnHold }, set: { _ in viewModel.toggleHold() })) {
                Label(viewModel.isOnHold ? "Resume" : "Hold", systemImage: "pause.fill")
            }
            .help("Hold (⌘R)")
            .disabled(!isConnected)

            Toggle(isOn: $showKeypad) {
                Label("Keypad", systemImage: "circle.grid.3x3.fill")
            }
            .help("Keypad (⌘K)")
            .keyboardShortcut("k")
            .popover(isPresented: $showKeypad, arrowEdge: .bottom) {
                KeypadView { key in
                    dtmfHistory.append(key)
                    viewModel.sendDTMF(key)
                }
                .padding(16)
            }

            AudioDeviceMenu(viewModel: viewModel)
                .fixedSize()
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .controlSize(.large)
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

// MARK: - Call Waiting

/// Shown at the top of the in-call screen when another call rings.
private struct CallWaitingBanner: View {
    let call: AppViewModel.CallInfo
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            CallerAvatar(title: call.labels.title, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(call.labels.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("Incoming call")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Button("Decline") { viewModel.declineCall(call.id) }
            Button("Answer") { viewModel.answerCall(call.id) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .controlSize(.small)
        .padding(12)
        .background(.green.opacity(0.12))
    }
}

// MARK: - Preview

#Preview("Call") {
    ActiveCallView(viewModel: AppViewModel.shared)
        .frame(width: 380, height: 560)
}
