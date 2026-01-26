//
//  ActiveAccountView.swift
//  TonePhone
//
//  Main screen when connected to an account.
//

import SwiftUI

/// Screen displayed when connected to a SIP account.
struct ActiveAccountView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Connected status
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.green)

                Text("Connected")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Spacer()

            // Account info
            if let account = viewModel.activeAccount {
                VStack(spacing: 8) {
                    Text(account.displayName.isEmpty ? account.username : account.displayName)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text(account.server)
                        Text("·")
                        Text(account.transport.displayName)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .padding(.horizontal)
            }

            Spacer()

            // Status indicator
            RegistrationStatusView(status: viewModel.registrationStatus)
                .padding(.bottom, 8)

            Divider()

            // Unregister button
            Button("Unregister") {
                viewModel.unregisterAndGoBack()
            }
            .controlSize(.large)
            .padding()
        }
    }
}

#Preview {
    ActiveAccountView(viewModel: AppViewModel())
        .frame(width: 350, height: 400)
}
