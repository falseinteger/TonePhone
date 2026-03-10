//
//  ActiveCallView.swift
//  TonePhone
//
//  Active call view with controls for macOS.
//

import SwiftUI

/// Active call view following macOS Human Interface Guidelines.
struct ActiveCallView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showDTMFKeypad = false
    @State private var showAudioDevicePicker = false
    @State private var dtmfHistory = ""

    private let compactThreshold: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < compactThreshold

            VStack(spacing: 0) {
                // Header with back button
                callHeader

                // Content
                contentArea

                Divider()

                // Controls
                controlBar(isCompact: isCompact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Call Header

    private var callHeader: some View {
        HStack {
            Button {
                viewModel.goBackToCallsList()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("Calls")
                        .font(.system(size: 13))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 16)

            // Avatar
            avatar

            // Name
            Text(displayName)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)

            // Status or Duration
            statusLabel

            // DTMF History
            if !dtmfHistory.isEmpty {
                dtmfHistoryLabel
            }

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 20)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)

            Text(initials)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            if isConnected {
                Text(viewModel.callDurationFormatted)
                    .font(.system(size: 13, design: .monospaced))
            } else {
                Text(statusText)
                    .font(.system(size: 13))
            }
        }
        .foregroundColor(.secondary)
    }

    private var dtmfHistoryLabel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(dtmfHistory)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .id("dtmf")
            }
            .onChange(of: dtmfHistory) { _ in
                // Auto-scroll to show most recent digits
                proxy.scrollTo("dtmf", anchor: .trailing)
            }
        }
        .frame(maxWidth: 200)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Control Bar

    private func controlBar(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            if isIncoming {
                incomingControls(isCompact: isCompact)
            } else {
                activeControls(isCompact: isCompact)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func incomingControls(isCompact: Bool) -> some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                viewModel.hangupCall()
            } label: {
                ControlLabel("Decline", icon: "phone.down.fill", isCompact: isCompact)
            }
            .buttonStyle(TintedButtonStyle(color: .red))
            .keyboardShortcut(.escape, modifiers: [])

            Button {
                viewModel.answerCall()
            } label: {
                ControlLabel("Answer", icon: "phone.fill", isCompact: isCompact)
            }
            .buttonStyle(TintedButtonStyle(color: .green))
            .keyboardShortcut(.return, modifiers: [])

            Spacer()
        }
    }

    private func activeControls(isCompact: Bool) -> some View {
        HStack(spacing: 6) {
            // Mute
            ToolbarToggle(
                isOn: viewModel.isMuted,
                icon: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                action: { viewModel.toggleMute() }
            )
            .keyboardShortcut("m", modifiers: .command)
            .help("Mute (⌘M)")

            // Hold
            ToolbarToggle(
                isOn: viewModel.isOnHold,
                icon: viewModel.isOnHold ? "play.fill" : "pause.fill",
                action: { viewModel.toggleHold() }
            )
            .keyboardShortcut("h", modifiers: .command)
            .help("Hold (⌘H)")

            // Keypad
            ToolbarToggle(
                isOn: showDTMFKeypad,
                icon: "circle.grid.3x3.fill",
                action: { showDTMFKeypad.toggle() }
            )
            .keyboardShortcut("k", modifiers: .command)
            .help("Keypad (⌘K)")
            .popover(isPresented: $showDTMFKeypad, arrowEdge: .top) {
                DTMFPopover(history: $dtmfHistory) { digit in
                    dtmfHistory.append(digit)
                    viewModel.sendDTMF(digit)
                }
            }

            // Audio device picker
            ToolbarToggle(
                isOn: showAudioDevicePicker,
                icon: "speaker.wave.2.fill",
                action: {
                    viewModel.refreshAudioDevices()
                    showAudioDevicePicker.toggle()
                }
            )
            .keyboardShortcut("a", modifiers: .command)
            .help("Audio Devices (⌘A)")
            .popover(isPresented: $showAudioDevicePicker, arrowEdge: .top) {
                AudioDevicePickerView(
                    viewModel: viewModel,
                    isPresented: $showAudioDevicePicker
                )
            }

            Spacer()

            // End
            Button {
                viewModel.hangupCall()
            } label: {
                ControlLabel("End", icon: "phone.down.fill", isCompact: isCompact)
            }
            .buttonStyle(TintedButtonStyle(color: .red))
            .keyboardShortcut(.escape, modifiers: [])
            .help("End Call (Esc)")
        }
    }

    // MARK: - Computed Properties

    private var isIncoming: Bool {
        if case .incoming = viewModel.callState { return true }
        return false
    }

    private var isConnected: Bool {
        viewModel.callState == .established || viewModel.callState == .held
    }

    private var displayName: String {
        let raw = viewModel.remotePartyName ?? viewModel.remotePartyURI ?? "Unknown"
        return PhoneNumberService.formatForDisplay(raw)
    }

    private var initials: String {
        let words = displayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(displayName.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased()
    }

    private var statusColor: Color {
        switch viewModel.callState {
        case .outgoing, .early: return .orange
        case .incoming, .established: return .green
        case .held: return .yellow
        case .idle, .ended: return .secondary
        }
    }

    private var statusText: String {
        switch viewModel.callState {
        case .idle: return "Idle"
        case .outgoing: return "Calling..."
        case .incoming: return "Incoming"
        case .early: return "Ringing..."
        case .established: return "Connected"
        case .held: return "On Hold"
        case .ended: return "Ended"
        }
    }
}

// MARK: - Control Label

private struct ControlLabel: View {
    let title: String
    let icon: String
    let isCompact: Bool

    init(_ title: String, icon: String, isCompact: Bool) {
        self.title = title
        self.icon = icon
        self.isCompact = isCompact
    }

    var body: some View {
        if isCompact {
            Image(systemName: icon)
        } else {
            Label(title, systemImage: icon)
        }
    }
}

// MARK: - Toolbar Toggle

private struct ToolbarToggle: View {
    let isOn: Bool
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 24)
                .foregroundColor(isOn ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isOn ? Color.accentColor : backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        Color(nsColor: isHovered ? .controlColor : .controlBackgroundColor)
    }
}

// MARK: - Tinted Button Style

private struct TintedButtonStyle: ButtonStyle {
    let color: Color
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(configuration.isPressed ? 0.7 : (isHovered ? 0.85 : 1.0)))
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - DTMF Popover

private struct DTMFPopover: View {
    @Binding var history: String
    let onDigit: (String) -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    private let letters: [String: String] = [
        "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
        "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ"
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Display - single line, scrollable, draggable
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(history.isEmpty ? "Enter digits" : history)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(history.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .id("dtmfDisplay")
                }
                .onChange(of: history) { _ in
                    proxy.scrollTo("dtmfDisplay", anchor: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor))
            )

            // Keypad
            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.self) { digit in
                            DTMFKey(digit: digit, letters: letters[digit]) {
                                onDigit(digit)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 196)
    }
}

// MARK: - DTMF Key

private struct DTMFKey: View {
    let digit: String
    let letters: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(digit)
                    .font(.system(size: 17, weight: .medium, design: .rounded))

                if let letters = letters {
                    Text(letters)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 52, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: isHovered ? .controlColor : .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview("Call") {
    ActiveCallView(viewModel: AppViewModel.shared)
        .frame(width: 300, height: 340)
}

#Preview("Compact") {
    ActiveCallView(viewModel: AppViewModel.shared)
        .frame(width: 220, height: 340)
}
