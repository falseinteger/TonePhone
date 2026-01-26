//
//  ActiveAccountView.swift
//  TonePhone
//
//  Main screen when connected to an account.
//

import SwiftUI

/// Screen displayed when connected to a SIP account.
///
/// Shows the dialpad for making calls along with account status.
/// Follows macOS Human Interface Guidelines for professional appearance.
struct ActiveAccountView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Account header bar
            accountHeader

            // Dialpad
            DialpadView { uri in
                viewModel.makeCall(to: formatURI(uri))
            }

            // Status bar
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Account Header

    private var accountHeader: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(viewModel.registrationStatus.indicatorColor)
                .frame(width: 8, height: 8)

            // Account info
            if let account = viewModel.activeAccount {
                Text(accountDisplayName(account))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("on")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(account.server)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Disconnect button
            Button {
                viewModel.unregisterAndGoBack()
            } label: {
                Text("Disconnect")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Disconnect from account")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accountAccessibilityLabel)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.registrationStatus.indicatorColor)
                .frame(width: 6, height: 6)

            Text(viewModel.registrationStatus.displayText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Helpers

    private func accountDisplayName(_ account: SIPAccount) -> String {
        account.displayName.isEmpty ? account.username : account.displayName
    }

    private var accountAccessibilityLabel: String {
        guard let account = viewModel.activeAccount else {
            return "No account"
        }
        let name = accountDisplayName(account)
        return "\(name) on \(account.server), \(viewModel.registrationStatus.displayText)"
    }

    /// Formats a user input into a proper SIP URI if needed.
    private func formatURI(_ input: String) -> String {
        // Remove any whitespace
        let cleaned = input.trimmingCharacters(in: .whitespaces)

        // If already a SIP URI, use as-is
        if cleaned.lowercased().hasPrefix("sip:") || cleaned.lowercased().hasPrefix("sips:") {
            return cleaned
        }

        // If contains @, assume it's a SIP address without scheme
        if cleaned.contains("@") {
            return "sip:\(cleaned)"
        }

        // Otherwise, assume it's a number and use the account's server
        if let account = viewModel.activeAccount {
            return "sip:\(cleaned)@\(account.server)"
        }

        // Fallback: just prepend sip:
        return "sip:\(cleaned)"
    }
}

#Preview {
    ActiveAccountView(viewModel: AppViewModel())
        .frame(width: 300, height: 480)
}
