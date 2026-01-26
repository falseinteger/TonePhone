//
//  ActiveCallView.swift
//  TonePhone
//
//  View displayed during an active call with call controls.
//  Design follows Apple Human Interface Guidelines.
//

import SwiftUI

/// View displayed during an active call.
///
/// Follows Apple HIG with a FaceTime-inspired design featuring:
/// - Large avatar with gradient background
/// - Clear visual hierarchy for caller info
/// - Circular control buttons with proper hit targets
/// - Smooth animations and transitions
struct ActiveCallView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showDTMFKeypad = false
    @State private var pulseAnimation = false

    // MARK: - Layout Constants

    private enum Layout {
        static let avatarSize: CGFloat = 120
        static let controlButtonSize: CGFloat = 64
        static let endCallButtonSize: CGFloat = 72
        static let buttonSpacing: CGFloat = 32
        static let contentSpacing: CGFloat = 8
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(minHeight: 24, maxHeight: 48)

            // Caller info section
            callerInfoSection

            Spacer()
                .frame(minHeight: 24, maxHeight: .infinity)

            // DTMF Keypad (expandable)
            if showDTMFKeypad {
                DTMFKeypadView(onDigitPressed: { digit in
                    viewModel.sendDTMF(digit)
                })
                .padding(.bottom, 24)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Call controls
            callControlsSection
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDTMFKeypad)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Caller Info Section

    private var callerInfoSection: some View {
        VStack(spacing: Layout.contentSpacing) {
            // Avatar with status ring
            avatarView
                .padding(.bottom, 8)

            // Caller name
            Text(remotePartyDisplay)
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Call status and duration
            callStatusView
        }
        .padding(.horizontal, 24)
    }

    private var avatarView: some View {
        ZStack {
            // Pulsing ring for connecting states
            if shouldShowPulse {
                Circle()
                    .stroke(callStateColor.opacity(0.3), lineWidth: 3)
                    .frame(width: Layout.avatarSize + 16, height: Layout.avatarSize + 16)
                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )
            }

            // Status ring
            Circle()
                .stroke(callStateColor, lineWidth: 3)
                .frame(width: Layout.avatarSize + 8, height: Layout.avatarSize + 8)

            // Avatar background
            Circle()
                .fill(avatarGradient)
                .frame(width: Layout.avatarSize, height: Layout.avatarSize)

            // Initials
            Text(remotePartyInitials)
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
        .onAppear {
            pulseAnimation = true
        }
    }

    private var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color.accentColor.opacity(0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shouldShowPulse: Bool {
        switch viewModel.callState {
        case .outgoing, .early, .incoming:
            return true
        default:
            return false
        }
    }

    private var callStatusView: some View {
        HStack(spacing: 6) {
            // Status indicator dot
            Circle()
                .fill(callStateColor)
                .frame(width: 8, height: 8)

            // Status text or duration
            Group {
                if isEstablishedOrHeld {
                    Text(viewModel.callDurationFormatted)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                } else {
                    Text(callStateText)
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .foregroundColor(.secondary)
        }
    }

    private var isEstablishedOrHeld: Bool {
        viewModel.callState == .established || viewModel.callState == .held
    }

    // MARK: - Call State Properties

    private var callStateColor: Color {
        switch viewModel.callState {
        case .outgoing, .early:
            return .orange
        case .incoming:
            return .green
        case .established:
            return .green
        case .held:
            return .yellow
        case .idle, .ended:
            return .secondary
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
        let filtered = name.filter { $0.isLetter || $0.isNumber }
        return String(filtered.prefix(2)).uppercased()
    }

    // MARK: - Call Controls Section

    private var isIncomingCall: Bool {
        if case .incoming = viewModel.callState {
            return true
        }
        return false
    }

    private var callControlsSection: some View {
        VStack(spacing: 24) {
            if isIncomingCall {
                incomingCallControls
            } else {
                activeCallControls
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Incoming Call Controls

    private var incomingCallControls: some View {
        HStack(spacing: Layout.buttonSpacing * 2) {
            // Decline button
            CallActionButton(
                icon: "phone.down.fill",
                backgroundColor: .red,
                size: Layout.endCallButtonSize,
                action: { viewModel.hangupCall() }
            )
            .accessibilityLabel("Decline call")

            // Answer button
            CallActionButton(
                icon: "phone.fill",
                backgroundColor: .green,
                size: Layout.endCallButtonSize,
                action: { viewModel.answerCall() }
            )
            .accessibilityLabel("Answer call")
        }
    }

    // MARK: - Active Call Controls

    private var activeCallControls: some View {
        VStack(spacing: 24) {
            // Control buttons row
            HStack(spacing: Layout.buttonSpacing) {
                // Mute
                CallControlButton(
                    icon: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: "Mute",
                    isActive: viewModel.isMuted,
                    action: { viewModel.toggleMute() }
                )

                // Keypad
                CallControlButton(
                    icon: "circle.grid.3x3.fill",
                    label: "Keypad",
                    isActive: showDTMFKeypad,
                    action: { showDTMFKeypad.toggle() }
                )

                // Hold
                CallControlButton(
                    icon: viewModel.isOnHold ? "play.fill" : "pause.fill",
                    label: viewModel.isOnHold ? "Resume" : "Hold",
                    isActive: viewModel.isOnHold,
                    action: { viewModel.toggleHold() }
                )
            }

            // End call button
            CallActionButton(
                icon: "phone.down.fill",
                backgroundColor: .red,
                size: Layout.endCallButtonSize,
                action: { viewModel.hangupCall() }
            )
            .accessibilityLabel("End call")
        }
    }
}

// MARK: - Call Control Button

/// Circular control button with label (Mute, Hold, Keypad).
private struct CallControlButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var isPressed = false

    private let size: CGFloat = 64

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(backgroundStyle)
                        .frame(width: size, height: size)

                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)

                // Label
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
        .accessibilityLabel("\(label), \(isActive ? "on" : "off")")
    }

    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        }
    }

    private var iconColor: Color {
        isActive ? .accentColor : .primary
    }
}

// MARK: - Call Action Button

/// Large circular action button (Answer, Decline, End Call).
private struct CallActionButton: View {
    let icon: String
    let backgroundColor: Color
    let size: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: size, height: size)
                    .shadow(color: backgroundColor.opacity(0.4), radius: 8, y: 4)

                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
    }
}

// MARK: - Pressable Button Style

/// Custom button style that tracks press state for visual feedback.
private struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { newValue in
                isPressed = newValue
            }
    }
}

// MARK: - DTMF Keypad

/// Grid of DTMF digit buttons following phone keypad layout.
struct DTMFKeypadView: View {
    let onDigitPressed: (String) -> Void

    private let keypadData: [[KeypadKey]] = [
        [.init("1", letters: ""), .init("2", letters: "ABC"), .init("3", letters: "DEF")],
        [.init("4", letters: "GHI"), .init("5", letters: "JKL"), .init("6", letters: "MNO")],
        [.init("7", letters: "PQRS"), .init("8", letters: "TUV"), .init("9", letters: "WXYZ")],
        [.init("*", letters: ""), .init("0", letters: "+"), .init("#", letters: "")]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(keypadData, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row) { key in
                        DTMFKeyButton(key: key, action: {
                            onDigitPressed(key.digit)
                        })
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

/// Model for a keypad key with digit and optional letters.
private struct KeypadKey: Identifiable, Hashable {
    let id = UUID()
    let digit: String
    let letters: String

    init(_ digit: String, letters: String) {
        self.digit = digit
        self.letters = letters
    }
}

/// Individual DTMF digit button with Apple Phone app styling.
private struct DTMFKeyButton: View {
    let key: KeypadKey
    let action: () -> Void

    @State private var isPressed = false

    private let size: CGFloat = 72

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isPressed ? 0.5 : 0.8))
                    .frame(width: size, height: size)

                VStack(spacing: 2) {
                    Text(key.digit)
                        .font(.system(size: 28, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)

                    if !key.letters.isEmpty {
                        Text(key.letters)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: isPressed)
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
        .accessibilityLabel("Dial \(key.digit)")
    }
}

// MARK: - Preview

#Preview("Established Call") {
    ActiveCallView(viewModel: {
        let vm = AppViewModel()
        return vm
    }())
    .frame(width: 380, height: 580)
}

#Preview("Incoming Call") {
    ActiveCallView(viewModel: {
        let vm = AppViewModel()
        return vm
    }())
    .frame(width: 380, height: 580)
}
