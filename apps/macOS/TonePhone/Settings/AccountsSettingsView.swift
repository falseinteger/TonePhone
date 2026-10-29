//
//  AccountsSettingsView.swift
//  TonePhone
//
//  Accounts pane: the accounts, with details, add and delete.
//

import SwiftUI

struct AccountsSettingsView: View {
    @ObservedObject private var viewModel = AppViewModel.shared
    @State private var editingAccount: SIPAccount?
    @State private var isAddingAccount = false
    @State private var accountPendingDeletion: SIPAccount?

    var body: some View {
        Form {
            Section {
                if viewModel.accounts.isEmpty {
                    Text("No Accounts")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.accounts) { account in
                    AccountSettingsRow(
                        account: account,
                        isConnected: viewModel.activeAccount?.id == account.id
                    ) {
                        editingAccount = account
                    }
                    .contextMenu {
                        Button("Details…") { editingAccount = account }
                        Divider()
                        Button("Delete…", role: .destructive) { accountPendingDeletion = account }
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Add Account…") {
                        isAddingAccount = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $editingAccount) { account in
            AccountConfigView(account: account)
                .onSave { updated, password in
                    viewModel.saveAccount(updated, password: password)
                }
                .onDelete { id in
                    viewModel.deleteAccount(id: id)
                }
        }
        .sheet(isPresented: $isAddingAccount) {
            AccountConfigView()
                .onSave { account, password in
                    viewModel.saveAccount(account, password: password)
                }
        }
        .confirmationDialog(
            "Delete \(accountPendingDeletion?.title ?? "account")?",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            presenting: accountPendingDeletion
        ) { account in
            Button("Delete", role: .destructive) {
                viewModel.deleteAccount(id: account.id)
            }
        } message: { _ in
            Text("The account and its saved password are removed from this Mac.")
        }
    }
}

private struct AccountSettingsRow: View {
    let account: SIPAccount
    let isConnected: Bool
    let onDetails: () -> Void

    private var status: String {
        if isConnected { return "Connected" }
        return account.autoLogin ? "Connects automatically" : "Not connected"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.title)
                Text("\(account.address) · \(status)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Button("Details…", action: onDetails)
        }
    }
}

#Preview("Accounts Settings") {
    AccountsSettingsView()
}
