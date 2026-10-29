//
//  AccountConfigView.swift
//  TonePhone
//
//  Sheet for adding or editing a SIP account, including connection options.
//

import SwiftUI

/// Sheet for configuring a SIP account.
///
/// Basic fields are always visible; connection options that most providers
/// don't need are in a collapsed "Advanced" group.
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

    @ObservedObject private var settings = SettingsStore.shared

    // Account
    @State private var displayName = ""
    @State private var autoLogin = false

    // Server
    @State private var server = ""
    @State private var port: Int?
    @State private var transport: SIPTransport = SettingsStore.shared.defaultTransport

    // Authentication
    @State private var username = ""
    @State private var password = ""
    @State private var authUsername = ""

    // Advanced
    @State private var showAdvanced = false
    @State private var outboundProxy = ""
    @State private var registrationInterval = SIPAccount.defaultRegistrationInterval
    @State private var mediaEncryption: MediaEncryption = .none
    @State private var dialFormatOverride: PhoneNumberDialFormat?
    @State private var dtmfModeOverride: DTMFMode?
    @State private var natMethodOverride: NATMethod?
    @State private var natPinholeOverride: Bool?
    @State private var stunServerOverride = ""

    // Delete confirmation
    @State private var showDeleteConfirmation = false

    private static let registrationIntervals = [60, 120, 300, 600, 1800, 3600]

    init(account: SIPAccount? = nil) {
        self.existingAccount = account
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Server", text: $server, prompt: Text("sip.example.com"))
                    TextField("Username", text: $username, prompt: Text("Required"))
                        .textContentType(.username)
                    SecureField("Password", text: $password, prompt: Text("Required"))
                        .textContentType(.password)
                    TextField("Display name", text: $displayName, prompt: Text("Optional"))
                } header: {
                    Text(isEditing ? "Account" : "New Account")
                } footer: {
                    if let problem = serverProblem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Transport", selection: $transport) {
                        ForEach(SIPTransport.allCases, id: \.self) { transport in
                            Text(transport.displayName).tag(transport)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Port", value: $port, format: .number.grouping(.never), prompt: Text(String(transport.defaultPort)))

                    Toggle("Connect automatically", isOn: $autoLogin)

                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        advancedFields
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Leave the port empty to use the default. Your provider’s setup guide lists the server, transport and port.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            footer
        }
        .frame(width: 460, height: showAdvanced ? 600 : 500)
        .onAppear { loadExistingAccount() }
        .confirmationDialog(
            "Delete \(existingAccount?.title ?? "this account")?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                if let account = existingAccount {
                    onDelete?(account.id)
                }
                dismiss()
            }
        } message: {
            Text("The account and its saved password are removed from this Mac. Your call history for it is kept.")
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedFields: some View {
        TextField("Authentication username", text: $authUsername, prompt: Text("Same as username"))
        TextField("Outbound proxy", text: $outboundProxy, prompt: Text("None"))

        Picker("Re-register every", selection: $registrationInterval) {
            ForEach(intervalOptions, id: \.self) { seconds in
                Text(Self.intervalName(seconds)).tag(seconds)
            }
        }

        Picker("Call encryption", selection: $mediaEncryption) {
            ForEach(MediaEncryption.allCases, id: \.self) { encryption in
                Text(encryption.displayName).tag(encryption)
            }
        }

        Picker("Dial numbers as", selection: $dialFormatOverride) {
            Text("Default (\(settings.phoneNumberDialFormat.displayName))").tag(PhoneNumberDialFormat?.none)
            Divider()
            ForEach(PhoneNumberDialFormat.allCases, id: \.self) { format in
                Text(format.displayName).tag(PhoneNumberDialFormat?.some(format))
            }
        }

        Picker("Keypad tones", selection: $dtmfModeOverride) {
            Text("Default (\(settings.dtmfMode.displayName))").tag(DTMFMode?.none)
            Divider()
            ForEach(DTMFMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(DTMFMode?.some(mode))
            }
        }

        Picker("NAT traversal", selection: $natMethodOverride) {
            Text("Default (\(settings.natMethod.displayName))").tag(NATMethod?.none)
            Divider()
            ForEach(NATMethod.allCases, id: \.self) { method in
                Text(method.displayName).tag(NATMethod?.some(method))
            }
        }

        Picker("Keep NAT mappings open", selection: $natPinholeOverride) {
            Text("Default (\(settings.natPinhole ? "On" : "Off"))").tag(Bool?.none)
            Divider()
            Text("On").tag(Bool?.some(true))
            Text("Off").tag(Bool?.some(false))
        }

        TextField("STUN server", text: $stunServerOverride, prompt: Text(settings.stunServers.first ?? "Default"))
    }

    /// Standard intervals plus the account's current value if it is custom.
    private var intervalOptions: [Int] {
        var options = Self.registrationIntervals
        if !options.contains(registrationInterval) {
            options.append(registrationInterval)
            options.sort()
        }
        return options
    }

    private static func intervalName(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour] : (seconds >= 60 ? [.minute] : [.second])
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds) s"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isEditing {
                Button("Delete Account…", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }

            Spacer()

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(isEditing ? "Save" : "Add Account") {
                saveAccount()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isFormValid)
        }
        .padding()
    }

    // MARK: - Validation

    private var trimmedServer: String {
        SIPAccount.normalizeHost(server)
    }

    /// Describes what is wrong with the server or port, if anything.
    private var serverProblem: String? {
        if let port, !(1...65535).contains(port) {
            return "The port must be between 1 and 65535."
        }
        let raw = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.contains(" ") {
            return "The server address can’t contain spaces."
        }
        if trimmedServer.isEmpty || trimmedServer.hasPrefix(".") || trimmedServer.hasSuffix(".") {
            return "Enter a server name like sip.example.com."
        }
        return nil
    }

    private var isFormValid: Bool {
        !trimmedServer.isEmpty &&
        serverProblem == nil &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    // MARK: - Actions

    private func loadExistingAccount() {
        guard let account = existingAccount else { return }

        server = account.server
        port = account.port
        username = account.username
        displayName = account.displayName
        transport = account.transport
        autoLogin = account.autoLogin
        authUsername = account.authUsername
        outboundProxy = account.outboundProxy
        registrationInterval = account.registrationInterval
        mediaEncryption = account.mediaEncryption
        dialFormatOverride = account.dialFormatOverride
        dtmfModeOverride = account.dtmfModeOverride
        natMethodOverride = account.natMethodOverride
        natPinholeOverride = account.natPinholeOverride
        stunServerOverride = account.stunServerOverride ?? ""

        // Open the advanced group when something in it is customized
        showAdvanced = !account.authUsername.isEmpty || !account.outboundProxy.isEmpty ||
            account.mediaEncryption != .none || account.dialFormatOverride != nil ||
            account.registrationInterval != SIPAccount.defaultRegistrationInterval || account.hasOverrides

        if let storedPassword = AccountStore.shared.getPassword(for: account.id) {
            password = storedPassword
        }
    }

    private func saveAccount() {
        guard isFormValid else { return }

        let stun = stunServerOverride.trimmingCharacters(in: .whitespaces)
        let account = SIPAccount(
            id: existingAccount?.id ?? UUID(),
            server: trimmedServer,
            port: port,
            username: username.trimmingCharacters(in: .whitespaces),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            transport: transport,
            autoLogin: autoLogin,
            authUsername: authUsername.trimmingCharacters(in: .whitespaces),
            outboundProxy: outboundProxy.trimmingCharacters(in: .whitespaces),
            registrationInterval: registrationInterval,
            mediaEncryption: mediaEncryption,
            dialFormatOverride: dialFormatOverride,
            stunServerOverride: stun.isEmpty ? nil : stun,
            natMethodOverride: natMethodOverride,
            natPinholeOverride: natPinholeOverride,
            dtmfModeOverride: dtmfModeOverride
        )

        onSave?(account, password)
        dismiss()
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
