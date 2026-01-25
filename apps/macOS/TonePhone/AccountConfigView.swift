//
//  AccountConfigView.swift
//  TonePhone
//
//  SwiftUI sheet for entering and editing SIP account details.
//

import SwiftUI

/// View for configuring a SIP account.
///
/// Displays input fields for SIP server, username, password, and display name.
/// Validates required fields before allowing save.
struct AccountConfigView: View {
    /// The environment dismiss action.
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
    @State private var isDefault: Bool = false
    @State private var autoLogin: Bool = false

    // Validation state
    @State private var showValidationError = false
    @State private var validationMessage = ""

    // Delete confirmation
    @State private var showDeleteConfirmation = false

    /// Creates a new account configuration view.
    /// - Parameter account: Existing account to edit, or nil for new account.
    init(account: SIPAccount? = nil) {
        self.existingAccount = account
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(isEditing ? "Edit Account" : "Add Account")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Form fields
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SIP Server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("sip.example.com", text: $server)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("SIP Server Address")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("SIP Username")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("SIP Password")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Your Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Display Name")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Transport")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Transport", selection: $transport) {
                        ForEach(SIPTransport.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Transport Protocol")
                }

                Divider()
                    .padding(.vertical, 4)

                // Account options
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-connect on launch", isOn: $autoLogin)
                        .accessibilityLabel("Auto-connect on app launch")

                    Toggle("Default account for calls", isOn: $isDefault)
                        .accessibilityLabel("Set as default account")
                }

                if showValidationError {
                    Text(validationMessage)
                        .foregroundColor(.red)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Buttons
            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .accessibilityLabel("Delete Account")
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .accessibilityLabel("Cancel")

                Button("Save") {
                    saveAccount()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
                .accessibilityLabel("Save Account")
            }
            .padding()
        }
        .frame(width: 400, height: 480)
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

    /// Whether the form has all required fields filled.
    private var isFormValid: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    /// Loads existing account data into form fields.
    private func loadExistingAccount() {
        guard let account = existingAccount else { return }

        server = account.server
        username = account.username
        displayName = account.displayName
        transport = account.transport
        isDefault = account.isDefault
        autoLogin = account.autoLogin

        // Load password from Keychain
        if let storedPassword = AccountStore.shared.getPassword(for: account.id) {
            password = storedPassword
        }
    }

    /// Validates and saves the account.
    private func saveAccount() {
        // Validate required fields
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

        // Create or update account
        let account = SIPAccount(
            id: existingAccount?.id ?? UUID(),
            server: trimmedServer,
            username: trimmedUsername,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            transport: transport,
            isDefault: isDefault,
            autoLogin: autoLogin
        )

        onSave?(account, password)
        dismiss()
    }

    /// Shows a validation error.
    private func showError(_ message: String) {
        validationMessage = message
        showValidationError = true
    }
}

// MARK: - View Modifiers

extension AccountConfigView {
    /// Sets the callback to be called when the account is saved.
    func onSave(_ handler: @escaping (SIPAccount, String) -> Void) -> AccountConfigView {
        var copy = self
        copy.onSave = handler
        return copy
    }

    /// Sets the callback to be called when the account is deleted.
    func onDelete(_ handler: @escaping (UUID) -> Void) -> AccountConfigView {
        var copy = self
        copy.onDelete = handler
        return copy
    }
}

#Preview("New Account") {
    AccountConfigView()
}

#Preview("Edit Account") {
    AccountConfigView(account: SIPAccount(
        server: "sip.example.com",
        username: "user",
        displayName: "Test User",
        isDefault: true
    ))
}
