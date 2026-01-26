//
//  AccountConfigView.swift
//  TonePhone
//
//  SwiftUI sheet for entering and editing SIP account details.
//

import SwiftUI

/// View for configuring a SIP account.
struct AccountConfigView: View {
    @Environment(\.dismiss) private var dismiss

    /// Callback when account is saved.
    var onSave: ((SIPAccount, String) -> Void)?

    /// Callback when account is deleted.
    var onDelete: ((UUID) -> Void)?

    /// The account being edited (nil for new account).
    private let existingAccount: SIPAccount?

    /// Whether we are editing an existing account.
    private var isEditing: Bool { existingAccount != nil }

    // Form fields
    @State private var server: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var displayName: String = ""
    @State private var transport: SIPTransport = .udp
    @State private var autoLogin: Bool = false

    // Validation state
    @State private var showValidationError = false
    @State private var validationMessage = ""

    // Delete confirmation
    @State private var showDeleteConfirmation = false

    init(account: SIPAccount? = nil) {
        self.existingAccount = account
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Form content
            ScrollView {
                VStack(spacing: 24) {
                    // Server section
                    FormSection(title: "Server") {
                        FormField(label: "SIP Server", placeholder: "sip.example.com", text: $server)

                        FormRow(label: "Transport") {
                            Picker("", selection: $transport) {
                                ForEach(SIPTransport.allCases, id: \.self) { t in
                                    Text(t.displayName).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                    }

                    // Credentials section
                    FormSection(title: "Credentials") {
                        FormField(label: "Username", placeholder: "username", text: $username)
                        FormSecureField(label: "Password", placeholder: "Required", text: $password)
                    }

                    // Profile section
                    FormSection(title: "Profile") {
                        FormField(label: "Display Name", placeholder: "Optional", text: $displayName)
                    }

                    // Options section
                    FormSection(title: "Options") {
                        FormToggle(
                            label: "Auto-connect",
                            description: "Connect automatically when app launches",
                            isOn: $autoLogin
                        )
                    }

                    // Validation error
                    if showValidationError {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(validationMessage)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 20)
            }

            Divider()

            // Footer buttons
            footerView
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadExistingAccount()
        }
        .confirmationDialog(
            "Delete Account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let account = existingAccount {
                    onDelete?(account.id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the account and its stored password. This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // Avatar preview
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)

                if !displayName.isEmpty || !username.isEmpty {
                    Text(previewInitials)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Edit Account" : "New Account")
                    .font(.headline)

                if !server.isEmpty || !username.isEmpty {
                    Text(previewSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var previewInitials: String {
        let name = displayName.isEmpty ? username : displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var previewSubtitle: String {
        if !username.isEmpty && !server.isEmpty {
            return "\(username)@\(server)"
        } else if !server.isEmpty {
            return server
        } else if !username.isEmpty {
            return username
        }
        return ""
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            if isEditing {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button("Save") {
                saveAccount()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    // MARK: - Actions

    private func loadExistingAccount() {
        guard let account = existingAccount else { return }

        server = account.server
        username = account.username
        displayName = account.displayName
        transport = account.transport
        autoLogin = account.autoLogin

        if let storedPassword = AccountStore.shared.getPassword(for: account.id) {
            password = storedPassword
        }
    }

    private func saveAccount() {
        // Clear previous validation error
        showValidationError = false

        let trimmedServer = server.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)

        if trimmedServer.isEmpty {
            showError("SIP server address is required.")
            return
        }

        if trimmedUsername.isEmpty {
            showError("Username is required.")
            return
        }

        if password.isEmpty {
            showError("Password is required.")
            return
        }

        let account = SIPAccount(
            id: existingAccount?.id ?? UUID(),
            server: trimmedServer,
            username: trimmedUsername,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            transport: transport,
            autoLogin: autoLogin
        )

        onSave?(account, password)
        dismiss()
    }

    private func showError(_ message: String) {
        validationMessage = message
        showValidationError = true
    }
}

// MARK: - Form Components

private struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 20)
        }
    }
}

private struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        FormRow(label: label) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
    }
}

private struct FormSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        FormRow(label: label) {
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct FormToggle: View {
    let label: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - View Modifiers

extension AccountConfigView {
    func onSave(_ handler: @escaping (SIPAccount, String) -> Void) -> AccountConfigView {
        var copy = self
        copy.onSave = handler
        return copy
    }

    func onDelete(_ handler: @escaping (UUID) -> Void) -> AccountConfigView {
        var copy = self
        copy.onDelete = handler
        return copy
    }
}

// MARK: - Preview

#Preview("New Account") {
    AccountConfigView()
}

#Preview("Edit Account") {
    AccountConfigView(account: SIPAccount(
        server: "sip.example.com",
        username: "user",
        displayName: "Test User",
        autoLogin: true
    ))
}
