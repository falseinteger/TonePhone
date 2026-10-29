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

    /// Port used when the account does not specify one.
    var defaultPort: Int {
        self == .tls ? 5061 : 5060
    }
}

/// Media (RTP) encryption for calls.
enum MediaEncryption: String, Codable, CaseIterable {
    case none = "none"
    case srtpOptional = "srtp"
    case srtpRequired = "srtp-mand"
    case dtlsSRTP = "dtls_srtp"

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .srtpOptional: return "SRTP When Available"
        case .srtpRequired: return "SRTP Required"
        case .dtlsSRTP: return "DTLS-SRTP"
        }
    }

    /// Value passed to the SIP engine, nil when encryption is off.
    var engineValue: String? {
        self == .none ? nil : rawValue
    }
}

/// Represents a SIP account configuration.
struct SIPAccount: Codable, Identifiable, Equatable {
    /// Unique identifier for the account.
    let id: UUID
    /// SIP domain or server address (e.g., "sip.example.com").
    var server: String
    /// Server port. Nil uses the transport's default (5060, or 5061 for TLS).
    var port: Int?
    /// SIP username (the user part of the address).
    var username: String
    /// Display name (optional).
    var displayName: String
    /// Transport protocol (UDP, TCP, TLS).
    var transport: SIPTransport
    /// Whether to automatically connect on app launch (also makes this the default account).
    var autoLogin: Bool

    // MARK: - Connection

    /// Authentication username, when the provider requires one that differs from the username.
    var authUsername: String
    /// Outbound proxy host (optionally with port). Empty means none.
    var outboundProxy: String
    /// How often to refresh the registration, in seconds.
    var registrationInterval: Int
    /// Media encryption policy.
    var mediaEncryption: MediaEncryption
    /// How dialed phone numbers are sent for this account. Nil uses the global setting.
    var dialFormatOverride: PhoneNumberDialFormat?

    // MARK: - Per-Account Overrides

    /// Override the global STUN server for this account.
    var stunServerOverride: String?
    /// Override the global NAT method for this account.
    var natMethodOverride: NATMethod?
    /// Override the global NAT pinhole setting for this account.
    var natPinholeOverride: Bool?
    /// Override the global DTMF mode for this account.
    var dtmfModeOverride: DTMFMode?

    /// Default registration interval. Short enough to keep NAT bindings
    /// alive on typical home routers.
    static let defaultRegistrationInterval = 600

    /// Creates a new account with default values.
    init(
        id: UUID = UUID(),
        server: String = "",
        port: Int? = nil,
        username: String = "",
        displayName: String = "",
        transport: SIPTransport = .udp,
        autoLogin: Bool = false,
        authUsername: String = "",
        outboundProxy: String = "",
        registrationInterval: Int = SIPAccount.defaultRegistrationInterval,
        mediaEncryption: MediaEncryption = .none,
        dialFormatOverride: PhoneNumberDialFormat? = nil,
        stunServerOverride: String? = nil,
        natMethodOverride: NATMethod? = nil,
        natPinholeOverride: Bool? = nil,
        dtmfModeOverride: DTMFMode? = nil
    ) {
        self.id = id
        self.server = server
        self.port = port
        self.username = username
        self.displayName = displayName
        self.transport = transport
        self.autoLogin = autoLogin
        self.authUsername = authUsername
        self.outboundProxy = outboundProxy
        self.registrationInterval = registrationInterval
        self.mediaEncryption = mediaEncryption
        self.dialFormatOverride = dialFormatOverride
        self.stunServerOverride = stunServerOverride
        self.natMethodOverride = natMethodOverride
        self.natPinholeOverride = natPinholeOverride
        self.dtmfModeOverride = dtmfModeOverride
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, server, port, username, displayName, transport, autoLogin
        case authUsername, outboundProxy, registrationInterval, mediaEncryption, dialFormatOverride
        case stunServerOverride, natMethodOverride, natPinholeOverride, dtmfModeOverride
    }

    /// Decodes leniently so accounts saved by older versions keep loading:
    /// missing keys get defaults and unknown enum values are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        server = try c.decode(String.self, forKey: .server)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        transport = (try? c.decode(SIPTransport.self, forKey: .transport)) ?? .udp
        autoLogin = try c.decodeIfPresent(Bool.self, forKey: .autoLogin) ?? false
        authUsername = try c.decodeIfPresent(String.self, forKey: .authUsername) ?? ""
        outboundProxy = try c.decodeIfPresent(String.self, forKey: .outboundProxy) ?? ""
        registrationInterval = try c.decodeIfPresent(Int.self, forKey: .registrationInterval)
            ?? SIPAccount.defaultRegistrationInterval
        mediaEncryption = (try? c.decode(MediaEncryption.self, forKey: .mediaEncryption)) ?? .none
        dialFormatOverride = try? c.decode(PhoneNumberDialFormat.self, forKey: .dialFormatOverride)
        stunServerOverride = try c.decodeIfPresent(String.self, forKey: .stunServerOverride)
        natMethodOverride = try? c.decode(NATMethod.self, forKey: .natMethodOverride)
        natPinholeOverride = try c.decodeIfPresent(Bool.self, forKey: .natPinholeOverride)
        dtmfModeOverride = try? c.decode(DTMFMode.self, forKey: .dtmfModeOverride)
    }

    // MARK: - Addresses

    /// Server host with any scheme, user part or whitespace removed.
    var normalizedServer: String {
        SIPAccount.normalizeHost(server)
    }

    /// Host and port used to reach the registrar, e.g. `sip.example.com:5080`.
    ///
    /// The port is omitted when it is the transport default and none was set,
    /// so DNS SRV lookups keep working.
    var hostPort: String {
        let host = normalizedServer
        guard let port, port > 0 else { return host }
        // Keep a port the user typed into the server field
        if SIPAccount.hostHasPort(host) { return host }
        let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(bracketed):\(port)"
    }

    /// Constructs the SIP address of record from server, port and username.
    var sipURI: String {
        "sip:\(SIPAccount.escapeUserPart(username))@\(hostPort)"
    }

    /// Short address for display, e.g. `alice@example.com`.
    var address: String {
        "\(username)@\(normalizedServer)"
    }

    /// Outbound proxy as a SIP URI with the account transport, or nil if none.
    var outboundProxyURI: String? {
        var proxy = outboundProxy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proxy.isEmpty else { return nil }
        if !proxy.lowercased().hasPrefix("sip:") && !proxy.lowercased().hasPrefix("sips:") {
            proxy = "sip:\(proxy)"
        }
        if transport != .udp && !proxy.lowercased().contains(";transport=") {
            proxy += ";transport=\(transport.rawValue)"
        }
        return proxy
    }

    /// Returns initials for avatar display.
    var initials: String {
        let name = displayName.isEmpty ? username : displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Name shown in lists: the display name, or the username when none is set.
    var title: String {
        displayName.isEmpty ? username : displayName
    }

    /// Whether this account has any overrides configured.
    var hasOverrides: Bool {
        stunServerOverride != nil ||
        natMethodOverride != nil ||
        natPinholeOverride != nil ||
        dtmfModeOverride != nil
    }

    // MARK: - Helpers

    /// Strips `sip:`/`sips:` schemes, `user@` parts, URI parameters and whitespace.
    static func normalizeHost(_ value: String) -> String {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["sips:", "sip:"] where host.lowercased().hasPrefix(scheme) {
            host = String(host.dropFirst(scheme.count))
        }
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if let semicolon = host.firstIndex(of: ";") {
            host = String(host[..<semicolon])
        }
        return host.filter { !$0.isWhitespace }
    }

    /// Whether a host string already ends in an explicit port.
    static func hostHasPort(_ host: String) -> Bool {
        if host.hasPrefix("[") {
            return host.range(of: "]:") != nil
        }
        // A single colon means host:port; several mean a bare IPv6 address
        return host.filter { $0 == ":" }.count == 1
    }

    /// Percent-escapes characters that are not allowed in a SIP URI user part (RFC 3261 §25.1).
    static func escapeUserPart(_ user: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()&=+$,;?/")
        return user.addingPercentEncoding(withAllowedCharacters: allowed) ?? user
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

        // If this account has autoLogin, clear autoLogin from others (only one primary account)
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
