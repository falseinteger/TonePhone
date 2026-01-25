//
//  AccountListView.swift
//  TonePhone
//
//  Account selection screen showing configured accounts.
//

import SwiftUI

/// Screen for selecting or adding SIP accounts.
struct AccountListView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if viewModel.accounts.isEmpty {
                emptyStateView
            } else {
                accountListView
            }

            Divider()

            // Footer
            footerView
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accounts")
                    .font(.headline)

                Text("Select an account to connect")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("No Accounts")
                    .font(.headline)

                Text("Add a SIP account to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button {
                viewModel.showAddAccountSheet()
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Account List

    private var accountListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.accounts) { account in
                    VStack(spacing: 0) {
                        AccountRowView(
                            account: account,
                            onConnect: {
                                viewModel.startConnection(for: account)
                            },
                            onEdit: {
                                viewModel.showEditAccountSheet(for: account)
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if account.id != viewModel.accounts.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                viewModel.showAddAccountSheet()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add Account")

            Spacer()

            Text("\(viewModel.accounts.count) account\(viewModel.accounts.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Account Row

struct AccountRowView: View {
    let account: SIPAccount
    let onConnect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatar

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.displayName.isEmpty ? account.username : account.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if account.isDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }

                    if account.autoLogin {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    }
                }

                Text("\(account.username)@\(account.server)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Edit button - always visible
            Button {
                onEdit()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Edit Account")

            // Connect button
            Button("Connect") {
                onConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)

            Text(account.initials)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.accentColor)
        }
    }
}

// MARK: - Preview

#Preview("With Accounts") {
    AccountListView(viewModel: AppViewModel())
        .frame(width: 380, height: 500)
}

#Preview("Empty") {
    AccountListView(viewModel: AppViewModel())
        .frame(width: 380, height: 500)
}
