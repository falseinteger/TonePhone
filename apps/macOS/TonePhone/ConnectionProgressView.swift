//
//  ConnectionProgressView.swift
//  TonePhone
//
//  Modal view showing connection progress and status.
//

import SwiftUI

/// Modal sheet displayed during connection attempts.
struct ConnectionProgressView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Status content
            VStack(spacing: 24) {
                // Status indicator
                statusIndicator

                // Status text
                VStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.system(size: 15, weight: .semibold))

                    if let account = viewModel.connectingAccount {
                        Text(account.displayName.isEmpty ? account.username : account.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Text(account.server)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    // Error message
                    if case .failed(let reason) = viewModel.registrationStatus {
                        Text(reason ?? "Unable to connect to server")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
            }

            Spacer()

            Divider()

            // Action buttons
            actionButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(width: 300, height: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.registrationStatus {
        case .registering:
            // Animated connecting state
            ZStack {
                // Pulse rings
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 72, height: 72)
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .opacity(isAnimating ? 0 : 0.5)

                // Avatar
                accountAvatar
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }

        case .registered:
            // Success state
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.green)
            }

        case .failed:
            // Error state
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.red)
            }

        case .notConfigured:
            // Not configured state
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "questionmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var accountAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 56, height: 56)

            if let account = viewModel.connectingAccount {
                Text(account.initials)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            switch viewModel.registrationStatus {
            case .registering:
                Spacer()
                Button("Cancel") {
                    viewModel.cancelConnection()
                }
                .keyboardShortcut(.escape)

            case .registered:
                Spacer()
                Button("Continue") {
                    viewModel.completeConnection()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)

            case .failed:
                Button("Edit Account") {
                    viewModel.editConnectingAccount()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Cancel") {
                    viewModel.cancelConnection()
                }
                .keyboardShortcut(.escape)

                Button("Retry") {
                    isAnimating = false
                    viewModel.retryConnection()
                }
                .buttonStyle(.borderedProminent)

            case .notConfigured:
                Spacer()
                Button("Close") {
                    viewModel.cancelConnection()
                }
                .keyboardShortcut(.escape)
            }
        }
    }

    // MARK: - Helpers

    private var statusTitle: String {
        switch viewModel.registrationStatus {
        case .notConfigured:
            return "Not Configured"
        case .registering:
            return "Connecting..."
        case .registered:
            return "Connected"
        case .failed:
            return "Connection Failed"
        }
    }

}

#Preview("Connecting") {
    ConnectionProgressView(viewModel: AppViewModel())
}
