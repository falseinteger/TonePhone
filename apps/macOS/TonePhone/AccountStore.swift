//
//  AccountStore.swift
//  TonePhone
//
//  Persistent storage for SIP account configuration.
//  Non-sensitive data is stored in JSON, passwords in Keychain.
//

import Foundation
import Security

/// Transport protocol for SIP connections.
enum SIPTransport: String, Codable, CaseIterable {
    case udp = "udp"
    case tcp = "tcp"
    case tls = "tls"

    /// Human-readable display name.
    var displayName: String {
        rawValue.uppercased()
    }
}

/// Represents a SIP account configuration.
struct SIPAccount: Codable, Identifiable, Equatable {
    /// Unique identifier for the account.
    let id: UUID
    /// SIP server address (e.g., "sip.example.com").
    var server: String
    /// SIP username.
    var username: String
    /// Display name (optional).
    var displayName: String
    /// Transport protocol (UDP, TCP, TLS).
    var transport: SIPTransport
    /// Whether this is the default account for outgoing calls.
    var isDefault: Bool
    /// Whether to automatically connect on app launch.
    var autoLogin: Bool

    /// Creates a new account with default values.
    init(
        id: UUID = UUID(),
        server: String = "",
        username: String = "",
        displayName: String = "",
        transport: SIPTransport = .udp,
        isDefault: Bool = false,
        autoLogin: Bool = false
    ) {
        self.id = id
        self.server = server
        self.username = username
        self.displayName = displayName
        self.transport = transport
        self.isDefault = isDefault
        self.autoLogin = autoLogin
    }

    /// Constructs the SIP URI from server and username.
    var sipURI: String {
        "sip:\(username)@\(server)"
    }
}

/// Manages persistent storage for SIP accounts.
///
/// Account metadata is stored in a JSON file.
/// Passwords are stored securely in the Keychain.
final class AccountStore {

    /// Shared singleton instance.
    static let shared = AccountStore()

    /// File URL for the accounts JSON file.
    private let accountsFileURL: URL

    /// Keychain service identifier.
    private let keychainService = "com.tonephone.accounts"

    private init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory not available")
        }

        let tonePhoneDir = appSupport.appendingPathComponent("TonePhone", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: tonePhoneDir,
            withIntermediateDirectories: true
        )

        accountsFileURL = tonePhoneDir.appendingPathComponent("accounts.json")
    }

    // MARK: - Account Persistence

    /// Loads all accounts from storage.
    func loadAccounts() -> [SIPAccount] {
        guard FileManager.default.fileExists(atPath: accountsFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: accountsFileURL)
            let accounts = try JSONDecoder().decode([SIPAccount].self, from: data)
            return accounts
        } catch {
            print("Failed to load accounts: \(error)")
            return []
        }
    }

    /// Saves all accounts to storage.
    func saveAccounts(_ accounts: [SIPAccount]) {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: accountsFileURL, options: .atomic)
        } catch {
            print("Failed to save accounts: \(error)")
        }
    }

    /// Saves a single account (add or update).
    func saveAccount(_ account: SIPAccount) {
        var accounts = loadAccounts()

        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }

        // If this account is default, clear default from others
        if account.isDefault {
            for i in accounts.indices where accounts[i].id != account.id {
                accounts[i].isDefault = false
            }
        }

        // If this account has autoLogin, clear autoLogin from others
        if account.autoLogin {
            for i in accounts.indices where accounts[i].id != account.id {
                accounts[i].autoLogin = false
            }
        }

        saveAccounts(accounts)
    }

    /// Deletes an account from storage.
    func deleteAccount(id: UUID) {
        var accounts = loadAccounts()
        accounts.removeAll { $0.id == id }
        saveAccounts(accounts)

        // Also remove password from Keychain
        deletePassword(for: id)
    }

    // MARK: - Password Storage

    /// Saves a password.
    /// In DEBUG builds, uses UserDefaults to avoid Keychain prompts.
    /// In Release builds, uses Keychain for secure storage.
    func savePassword(_ password: String, for accountID: UUID) {
        #if DEBUG
        savePasswordToUserDefaults(password, for: accountID)
        #else
        savePasswordToKeychain(password, for: accountID)
        #endif
    }

    /// Retrieves a password.
    func getPassword(for accountID: UUID) -> String? {
        #if DEBUG
        return getPasswordFromUserDefaults(for: accountID)
        #else
        return getPasswordFromKeychain(for: accountID)
        #endif
    }

    /// Deletes a password.
    func deletePassword(for accountID: UUID) {
        #if DEBUG
        deletePasswordFromUserDefaults(for: accountID)
        #else
        deletePasswordFromKeychain(for: accountID)
        #endif
    }

    // MARK: - UserDefaults Storage (DEBUG only)

    private func savePasswordToUserDefaults(_ password: String, for accountID: UUID) {
        let key = "password_\(accountID.uuidString)"
        UserDefaults.standard.set(password, forKey: key)
    }

    private func getPasswordFromUserDefaults(for accountID: UUID) -> String? {
        let key = "password_\(accountID.uuidString)"
        return UserDefaults.standard.string(forKey: key)
    }

    private func deletePasswordFromUserDefaults(for accountID: UUID) {
        let key = "password_\(accountID.uuidString)"
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Keychain Storage (Release only)

    private func savePasswordToKeychain(_ password: String, for accountID: UUID) {
        let key = accountID.uuidString
        guard let passwordData = password.data(using: .utf8) else {
            print("Failed to encode password as UTF-8")
            return
        }

        // Query to find existing item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        // Attributes to update
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        // Try to update existing item first
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = passwordData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                print("Failed to save password to Keychain: \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            print("Failed to update password in Keychain: \(updateStatus)")
        }
    }

    private func getPasswordFromKeychain(for accountID: UUID) -> String? {
        let key = accountID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    private func deletePasswordFromKeychain(for accountID: UUID) {
        let key = accountID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
