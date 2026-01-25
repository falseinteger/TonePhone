//
//  LaunchConnectingView.swift
//  TonePhone
//
//  Loading screen shown during auto-login on app launch.
//

import SwiftUI

/// Full-screen view shown when auto-connecting on launch.
struct LaunchConnectingView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            // Status
            VStack(spacing: 8) {
                Text("Connecting")
                    .font(.title2)
                    .fontWeight(.medium)

                if let account = viewModel.connectingAccount {
                    Text(account.displayName.isEmpty ? account.username : account.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(account.server)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Progress indicator
            ProgressView()
                .scaleEffect(1.2)
                .padding(.top, 8)

            Spacer()

            // Cancel button
            Button("Cancel") {
                viewModel.cancelAutoConnect()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    LaunchConnectingView(viewModel: AppViewModel())
        .frame(width: 380, height: 500)
}
