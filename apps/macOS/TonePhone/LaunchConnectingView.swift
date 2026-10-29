//
//  LaunchConnectingView.swift
//  TonePhone
//
//  Screen shown while connecting automatically at launch.
//

import SwiftUI

/// Shown while the auto-connect account registers at launch.
struct LaunchConnectingView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let account = viewModel.connectingAccount {
                CallerAvatar(title: account.title, size: 72)

                VStack(spacing: 4) {
                    Text(account.title)
                        .font(.title3.weight(.semibold))
                    Text(account.address)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Connecting")

            Spacer()

            Button("Use Another Account") {
                viewModel.cancelAutoConnect()
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Connecting…")
        .navigationSubtitle("")
    }
}

#Preview {
    LaunchConnectingView(viewModel: AppViewModel.shared)
        .frame(width: 380, height: 500)
}
