//
//  AccountsSettingsView.swift
//  TonePhone
//
//  Accounts pane: list of accounts with add, remove and edit.
//

import SwiftUI

struct AccountsSettingsView: View {
    @ObservedObject private var viewModel = AppViewModel.shared
    @State private var selection: SIPAccount.ID?
    @State private var editingAccount: SIPAccount?
    @State private var isAddingAccount = false
    @State private var accountPendingDeletion: SIPAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(viewModel.accounts) { account in
                    AccountSettingsRow(
                        account: account,
                        isConnected: viewModel.activeAccount?.id == account.id
                    )
                    .tag(account.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: SIPAccount.ID.self) { ids in
                if let account = account(for: ids.first) {
                    Button("Edit…") { editingAccount = account }
                    Divider()
                    Button("Delete…", role: .destructive) { accountPendingDeletion = account }
                }
            } primaryAction: { ids in
                editingAccount = account(for: ids.first)
            }
            .onDeleteCommand {
                accountPendingDeletion = account(for: selection)
            }
            .overlay {
                if viewModel.accounts.isEmpty {
                    Text("No Accounts")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Add/remove buttons beneath the list
            HStack(spacing: 0) {
                Button {
                    isAddingAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 20)
                }
                .help("Add Account")

                Divider().frame(height: 16)

                Button {
                    accountPendingDeletion = account(for: selection)
                } label: {
                    Label("Delete Account", systemImage: "minus")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 20)
                }
                .disabled(selection == nil)
                .help("Delete Account")

                Spacer()

                Button("Edit…") {
                    editingAccount = account(for: selection)
                }
                .disabled(selection == nil)
            }
            .buttonStyle(.borderless)
            .padding(.top, 8)
        }
        .padding(20)
        .frame(height: 320)
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
                selection = nil
            }
        } message: { _ in
            Text("The account and its saved password are removed from this Mac.")
        }
    }

    private func account(for id: SIPAccount.ID?) -> SIPAccount? {
        guard let id else { return nil }
        return viewModel.accounts.first { $0.id == id }
    }
}

private struct AccountSettingsRow: View {
    let account: SIPAccount
    let isConnected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.title)
                Text(account.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            if account.autoLogin {
                Text("Connects automatically")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Accounts Settings") {
    AccountsSettingsView()
}
