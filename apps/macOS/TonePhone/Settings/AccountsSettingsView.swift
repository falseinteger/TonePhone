//
//  AccountsSettingsView.swift
//  TonePhone
//
//  Account list and per-account settings access.
//

import SwiftUI

struct AccountsSettingsView: View {
    @State private var accounts: [SIPAccount] = []
    @State private var editingAccount: SIPAccount?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Accounts")
                    .font(.title2)
                    .fontWeight(.bold)

                if accounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { accounts = AccountStore.shared.loadAccounts() }
        .sheet(item: $editingAccount) { account in
            AccountSettingsDetailView(account: account) { updated in
                AccountStore.shared.saveAccount(updated)
                accounts = AccountStore.shared.loadAccounts()
                NotificationCenter.default.post(name: .accountSettingsChanged, object: updated.id)
            }
            .frame(minWidth: 480, minHeight: 480)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No Accounts")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Add an account from the main window to configure account-specific settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Account List

    private var accountList: some View {
        SettingsSection(title: "Configured Accounts") {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Divider().padding(.horizontal, 12)
                }
                accountRow(account)
            }
        }
    }

    private func accountRow(_ account: SIPAccount) -> some View {
        Button {
            editingAccount = account
        } label: {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Text(account.initials)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName.isEmpty ? account.username : account.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text(account.server)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if account.hasOverrides {
                            Text("(custom)")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                Spacer()

                if account.autoLogin {
                    Text("Default")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(4)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Accounts Settings") {
    AccountsSettingsView()
        .frame(width: 500, height: 400)
}
