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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Status indicator
            Group {
                switch viewModel.registrationStatus {
                case .registering:
                    ProgressView()
                        .scaleEffect(1.5)

                case .registered:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)

                case .notConfigured:
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 60)

            // Status text
            VStack(spacing: 8) {
                Text(statusTitle)
                    .font(.headline)

                if let account = viewModel.connectingAccount {
                    Text(account.server)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if case .failed(let reason) = viewModel.registrationStatus {
                    Text(reason ?? "Connection failed")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                switch viewModel.registrationStatus {
                case .registering:
                    Button("Cancel") {
                        viewModel.cancelConnection()
                    }
                    .keyboardShortcut(.escape)

                case .registered:
                    Button("Continue") {
                        viewModel.completeConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)

                case .failed:
                    Button("Back") {
                        viewModel.cancelConnection()
                    }
                    .keyboardShortcut(.escape)

                    Button("Edit") {
                        viewModel.editConnectingAccount()
                    }

                    Button("Retry") {
                        viewModel.retryConnection()
                    }
                    .buttonStyle(.borderedProminent)

                case .notConfigured:
                    Button("Close") {
                        viewModel.cancelConnection()
                    }
                    .keyboardShortcut(.escape)
                }
            }
            .padding(.bottom)
        }
        .frame(width: 280, height: 220)
        .padding()
    }

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
    ConnectionProgressView(viewModel: {
        let vm = AppViewModel()
        return vm
    }())
}
