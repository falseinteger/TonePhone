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
struct ActiveAccountView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Account header
            accountHeader
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()

            // Dialpad
            DialpadView { uri in
                viewModel.makeCall(to: formatURI(uri))
            }

            Divider()

            // Footer with status and unregister
            footer
        }
    }

    // MARK: - Account Header

    private var accountHeader: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(viewModel.registrationStatus.indicatorColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            // Account name
            if let account = viewModel.activeAccount {
                Text(account.displayName.isEmpty ? account.username : account.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text("·")
                    .foregroundColor(.secondary)

                Text(account.server)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accountAccessibilityLabel)
    }

    private var accountAccessibilityLabel: String {
        guard let account = viewModel.activeAccount else {
            return "No account"
        }
        let name = account.displayName.isEmpty ? account.username : account.displayName
        return "\(name) on \(account.server), \(viewModel.registrationStatus.displayText)"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Status text
            Text(viewModel.registrationStatus.displayText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            // Unregister button
            Button("Disconnect") {
                viewModel.unregisterAndGoBack()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    /// Formats a user input into a proper SIP URI if needed.
    private func formatURI(_ input: String) -> String {
        // If already a SIP URI, use as-is
        if input.lowercased().hasPrefix("sip:") || input.lowercased().hasPrefix("sips:") {
            return input
        }

        // If contains @, assume it's a SIP address without scheme
        if input.contains("@") {
            return "sip:\(input)"
        }

        // Otherwise, assume it's a number and use the account's server
        if let account = viewModel.activeAccount {
            return "sip:\(input)@\(account.server)"
        }

        // Fallback: just prepend sip:
        return "sip:\(input)"
    }
}

#Preview {
    ActiveAccountView(viewModel: AppViewModel())
        .frame(width: 300, height: 450)
}
