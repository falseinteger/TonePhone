//
//  ContentView.swift
//  TonePhone
//
//  Main content view for the TonePhone application.
//

import SwiftUI

/// Main content view for the TonePhone application window.
///
/// Displays the app branding, account configuration, and registration status.
/// The status updates in real-time as account state changes are received.
struct ContentView: View {
    /// View model that tracks account registration state.
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        VStack {
            Spacer()

            // App icon
            Image(systemName: "phone.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("TonePhone")
                .font(.title)
                .padding(.top, 8)

            Spacer()

            // Account configuration button
            if viewModel.accounts.isEmpty {
                Button("Add Account") {
                    viewModel.showAddAccountSheet()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add SIP Account")
            } else {
                // Show configured account with edit option
                if let account = viewModel.accounts.first {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName.isEmpty ? account.username : account.displayName)
                                .font(.headline)
                            Text(account.server)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            viewModel.showEditAccountSheet(for: account)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit Account")
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .padding(.horizontal)
                }
            }

            Spacer()

            // Registration status at the bottom
            RegistrationStatusView(status: viewModel.registrationStatus)
                .padding(.bottom, 20)
        }
        .padding()
        .sheet(isPresented: $viewModel.isAccountSheetPresented) {
            AccountConfigView(account: viewModel.selectedAccount)
                .onSave { account, password in
                    viewModel.saveAccount(account, password: password)
                }
                .onDelete { accountID in
                    viewModel.deleteAccount(id: accountID)
                }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }
}

#Preview {
    ContentView()
}
