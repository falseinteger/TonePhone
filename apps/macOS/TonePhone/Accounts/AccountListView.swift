//
//  AccountListView.swift
//  TonePhone
//
//  Account selection screen showing configured accounts.
//

import SwiftUI

/// Screen for choosing an account to connect.
///
/// Double-click or Return connects. Connection progress and errors are
/// shown in the account's row.
struct AccountListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selection: SIPAccount.ID?
    @State private var accountPendingDeletion: SIPAccount?

    var body: some View {
        Group {
            if viewModel.accounts.isEmpty {
                emptyState
            } else {
                accountList
            }
        }
        .navigationTitle("Accounts")
        .navigationSubtitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showAddAccountSheet()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .help("Add Account (⌘N)")
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "phone.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Accounts")
                .font(.title2.weight(.semibold))

            Text("Add the SIP account from your phone provider to make and receive calls.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Button("Add Account…") {
                viewModel.showAddAccountSheet()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Account List

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an Account")
                .font(.title2.weight(.semibold))
            Text("Double-click an account to connect. Calls and recents are kept per account.")
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(viewModel.accounts) { account in
                    AccountRowView(account: account, viewModel: viewModel)
                        .tag(account.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(minHeight: 160, maxHeight: 360)
            .contextMenu(forSelectionType: SIPAccount.ID.self) { ids in
                if let account = account(for: ids.first) {
                    Button("Connect") { viewModel.startConnection(for: account) }
                    Button("Edit…") { viewModel.showEditAccountSheet(for: account) }
                    Divider()
                    Button("Delete…", role: .destructive) { accountPendingDeletion = account }
                }
            } primaryAction: { ids in
                if let account = account(for: ids.first) {
                    viewModel.startConnection(for: account)
                }
            }
            .onDeleteCommand {
                accountPendingDeletion = account(for: selection)
            }
        }
        .padding(32)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func account(for id: SIPAccount.ID?) -> SIPAccount? {
        guard let id else { return nil }
        return viewModel.accounts.first { $0.id == id }
    }
}

// MARK: - Account Row

struct AccountRowView: View {
    let account: SIPAccount
    @ObservedObject var viewModel: AppViewModel

    private var isConnecting: Bool {
        viewModel.connectingAccount?.id == account.id
    }

    private var failure: String? {
        guard isConnecting, case .failed(let reason) = viewModel.registrationStatus else { return nil }
        return reason ?? "Couldn’t connect."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CallerAvatar(title: account.title, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.title)
                        .lineLimit(1)
                    Text(account.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                trailingControl
            }

            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Edit Account…") { viewModel.editConnectingAccount() }
                        Button("Cancel") { viewModel.cancelConnection() }
                        Button("Try Again") { viewModel.retryConnection() }
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isConnecting && failure == nil {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Button("Cancel") { viewModel.cancelConnection() }
                    .controlSize(.small)
            }
            .accessibilityLabel("Connecting")
        } else if failure == nil {
            Button("Connect") {
                viewModel.startConnection(for: account)
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Preview

#Preview("Accounts") {
    AccountListView(viewModel: AppViewModel.shared)
        .frame(width: 380, height: 500)
}
