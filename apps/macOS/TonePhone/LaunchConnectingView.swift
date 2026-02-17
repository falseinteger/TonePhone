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
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Main content
            VStack(spacing: 32) {
                // Account avatar with pulse animation
                ZStack {
                    // Pulse rings
                    Circle()
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        .frame(width: 100, height: 100)
                        .scaleEffect(isAnimating ? 1.3 : 1.0)
                        .opacity(isAnimating ? 0 : 0.5)

                    Circle()
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                        .frame(width: 100, height: 100)
                        .scaleEffect(isAnimating ? 1.6 : 1.0)
                        .opacity(isAnimating ? 0 : 0.3)

                    // Avatar
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 80, height: 80)

                        if let account = viewModel.connectingAccount {
                            Text(account.initials)
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundColor(.accentColor)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                }

                // Status text
                VStack(spacing: 6) {
                    if let account = viewModel.connectingAccount {
                        Text(account.displayName.isEmpty ? account.username : account.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(account.server)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    // Connection status
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                            .padding(4)

                        Text("Connecting...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }

            Spacer()

            // Footer
            VStack(spacing: 16) {
                Divider()

                HStack {
                    Button {
                        viewModel.cancelAutoConnect()
                    } label: {
                        Text("Use Different Account")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    LaunchConnectingView(viewModel: AppViewModel.shared)
        .frame(width: 380, height: 500)
}
