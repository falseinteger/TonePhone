//
//  SettingsStore.swift
//  TonePhone
//
//  Manages app settings persistence using UserDefaults.
//

import Foundation
import SwiftUI

/// DTMF transmission mode for SIP calls.
///
/// Raw values are kept stable for saved settings; `engineValue` is what the
/// SIP engine understands.
enum DTMFMode: String, Codable, CaseIterable {
    case rfc2833 = "rfc2833"
    case sipInfo = "info"
    case automatic = "auto"

    var displayName: String {
        switch self {
        case .rfc2833: return "RTP Events (RFC 2833)"
        case .sipInfo: return "SIP INFO"
        case .automatic: return "Automatic"
        }
    }

    var description: String {
        switch self {
        case .rfc2833: return "Send keypad tones as RTP events. Works with most providers."
        case .sipInfo: return "Send keypad tones as SIP INFO messages."
        case .automatic: return "Use RTP events when the other side supports them, otherwise SIP INFO."
        }
    }

    var engineValue: String {
        switch self {
        case .rfc2833: return "rtpevent"
        case .sipInfo: return "info"
        case .automatic: return "auto"
        }
    }
}

/// NAT traversal method for media.
enum NATMethod: String, Codable, CaseIterable {
    case stun = "stun"
    case ice = "ice"
    case none = "none"

    var displayName: String {
        switch self {
        case .stun: return "STUN"
        case .ice: return "ICE"
        case .none: return "None"
        }
    }

    var description: String {
        switch self {
        case .stun: return "Simple NAT traversal"
        case .ice: return "Full ICE connectivity checks"
        case .none: return "Direct connection (no NAT)"
        }
    }
}

/// Centralized app settings storage using UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let logLevel = "settings.logLevel"
        static let defaultTransport = "settings.defaultTransport"
        static let stunServer = "settings.stunServer"
        static let stunServers = "settings.stunServers"
        static let natMethod = "settings.natMethod"
        static let natPinhole = "settings.natPinhole"
        static let dtmfMode = "settings.dtmfMode"
        static let verifyTLSServer = "settings.verifyTLSServer"
        static let additionalCAFile = "settings.additionalCAFile"
        static let advancedMode = "settings.advancedMode"
        static let sipTrace = "settings.sipTrace"
        static let registerOnStartup = "settings.registerOnStartup"
        static let selectedRingtone = "settings.selectedRingtone"
        static let echoCancellation = "settings.echoCancellation"
    }

    // MARK: - Default Values

    private enum Defaults {
        static let logLevel = LogLevel.info.rawValue
        static let defaultTransport = "udp"
        static let stunServer = "stun:stun.l.google.com:19302"
        static let stunServers = ["stun:stun.l.google.com:19302"]
        static let natMethod = "stun"
        static let natPinhole = true
        static let dtmfMode = "rfc2833"
        static let verifyTLSServer = true
        static let registerOnStartup = true
        static let selectedRingtone = "Ping.aiff"
        static let echoCancellation = true
    }

    // MARK: - Published Properties

    /// Log level for the SIP stack.
    @Published var logLevel: LogLevel {
        didSet {
            defaults.set(logLevel.rawValue, forKey: Keys.logLevel)
            applyLogLevel()
        }
    }

    /// Default transport for new accounts.
    @Published var defaultTransport: SIPTransport {
        didSet {
            defaults.set(defaultTransport.rawValue, forKey: Keys.defaultTransport)
        }
    }

    /// STUN server address (legacy, kept for bridge compatibility).
    @Published var stunServer: String {
        didSet {
            defaults.set(stunServer, forKey: Keys.stunServer)
        }
    }

    /// STUN servers list.
    @Published var stunServers: [String] {
        didSet {
            defaults.set(stunServers, forKey: Keys.stunServers)
            // Keep legacy stunServer in sync with first entry
            if let first = stunServers.first, first != stunServer {
                stunServer = first
            }
        }
    }

    /// NAT traversal method.
    @Published var natMethod: NATMethod {
        didSet {
            defaults.set(natMethod.rawValue, forKey: Keys.natMethod)
        }
    }

    /// Enable NAT pinhole keep-alive.
    @Published var natPinhole: Bool {
        didSet {
            defaults.set(natPinhole, forKey: Keys.natPinhole)
        }
    }

    /// DTMF transmission mode.
    @Published var dtmfMode: DTMFMode {
        didSet {
            defaults.set(dtmfMode.rawValue, forKey: Keys.dtmfMode)
        }
    }

    /// Verify the server certificate on TLS connections. Applies on next launch.
    @Published var verifyTLSServer: Bool {
        didSet {
            defaults.set(verifyTLSServer, forKey: Keys.verifyTLSServer)
        }
    }

    /// PEM file with extra certificate authorities, kept in Application
    /// Support. Applies on next launch.
    @Published private(set) var additionalCAFile: String? {
        didSet {
            defaults.set(additionalCAFile, forKey: Keys.additionalCAFile)
        }
    }

    /// Shows diagnostic tools: the log viewer and SIP message tracing.
    @Published var advancedMode: Bool {
        didSet {
            defaults.set(advancedMode, forKey: Keys.advancedMode)
            if !advancedMode { sipTrace = false }
        }
    }

    /// Write every SIP message to the log.
    @Published var sipTrace: Bool {
        didSet {
            defaults.set(sipTrace, forKey: Keys.sipTrace)
            // Tracing is applied at launch only with diagnostics shown
            if sipTrace && !advancedMode { advancedMode = true }
            TonePhoneCore.shared.setSIPTraceEnabled(sipTrace)
        }
    }

    /// Auto-register accounts on app startup.
    @Published var registerOnStartup: Bool {
        didSet {
            defaults.set(registerOnStartup, forKey: Keys.registerOnStartup)
        }
    }

    /// Selected ringtone filename from /System/Library/Sounds/.
    @Published var selectedRingtone: String {
        didSet {
            defaults.set(selectedRingtone, forKey: Keys.selectedRingtone)
        }
    }

    /// Remove the other person's voice from the microphone; applies from the next call.
    @Published var echoCancellation: Bool {
        didSet {
            defaults.set(echoCancellation, forKey: Keys.echoCancellation)
            TonePhoneCore.shared.setEchoCancellation(echoCancellation)
        }
    }

    /// Phone number region code for formatting (e.g. "US", "GB"). Empty means system locale.
    @Published var phoneNumberRegion: String {
        didSet {
            defaults.set(phoneNumberRegion, forKey: PhoneNumberSettingsKey.region)
            notifyPhoneNumberFormatChanged()
        }
    }

    /// How phone numbers are shown.
    @Published var phoneNumberDisplayFormat: PhoneNumberDisplayFormat {
        didSet {
            defaults.set(phoneNumberDisplayFormat.rawValue, forKey: PhoneNumberSettingsKey.displayFormat)
            notifyPhoneNumberFormatChanged()
        }
    }

    /// How dialed numbers are sent to the server (accounts can override).
    @Published var phoneNumberDialFormat: PhoneNumberDialFormat {
        didSet {
            defaults.set(phoneNumberDialFormat.rawValue, forKey: PhoneNumberSettingsKey.dialFormat)
        }
    }

    /// Digits that replace `+` with the international prefix dial format. Empty uses the region default.
    @Published var internationalPrefix: String {
        didSet {
            defaults.set(internationalPrefix, forKey: PhoneNumberSettingsKey.internationalPrefix)
        }
    }

    /// Format numbers in the dialpad while typing.
    @Published var formatAsYouType: Bool {
        didSet {
            defaults.set(formatAsYouType, forKey: PhoneNumberSettingsKey.formatAsYouType)
        }
    }

    // MARK: - Initialization

    private init() {
        // Load saved values or use defaults
        let logLevelInt = defaults.object(forKey: Keys.logLevel) as? Int ?? Defaults.logLevel
        self.logLevel = LogLevel(rawValue: logLevelInt) ?? .info

        let transportString = defaults.string(forKey: Keys.defaultTransport) ?? Defaults.defaultTransport
        self.defaultTransport = SIPTransport(rawValue: transportString) ?? .udp

        self.stunServer = defaults.string(forKey: Keys.stunServer) ?? Defaults.stunServer

        // STUN servers (migrate from single stunServer if needed)
        if let savedServers = defaults.stringArray(forKey: Keys.stunServers) {
            self.stunServers = savedServers
        } else {
            let legacyServer = defaults.string(forKey: Keys.stunServer) ?? Defaults.stunServer
            self.stunServers = [legacyServer]
        }

        let natMethodString = defaults.string(forKey: Keys.natMethod) ?? Defaults.natMethod
        self.natMethod = NATMethod(rawValue: natMethodString) ?? .stun

        // For booleans, check if key exists to distinguish "false" from "not set"
        if defaults.object(forKey: Keys.natPinhole) != nil {
            self.natPinhole = defaults.bool(forKey: Keys.natPinhole)
        } else {
            self.natPinhole = Defaults.natPinhole
        }

        let dtmfModeString = defaults.string(forKey: Keys.dtmfMode) ?? Defaults.dtmfMode
        self.dtmfMode = DTMFMode(rawValue: dtmfModeString) ?? .rfc2833

        self.verifyTLSServer = defaults.object(forKey: Keys.verifyTLSServer) as? Bool ?? Defaults.verifyTLSServer
        self.additionalCAFile = defaults.string(forKey: Keys.additionalCAFile)
        self.advancedMode = defaults.bool(forKey: Keys.advancedMode)
        self.sipTrace = defaults.bool(forKey: Keys.sipTrace)

        if defaults.object(forKey: Keys.registerOnStartup) != nil {
            self.registerOnStartup = defaults.bool(forKey: Keys.registerOnStartup)
        } else {
            self.registerOnStartup = Defaults.registerOnStartup
        }

        self.selectedRingtone = defaults.string(forKey: Keys.selectedRingtone) ?? Defaults.selectedRingtone
        self.echoCancellation = defaults.object(forKey: Keys.echoCancellation) != nil
            ? defaults.bool(forKey: Keys.echoCancellation)
            : Defaults.echoCancellation
        self.phoneNumberRegion = defaults.string(forKey: PhoneNumberSettingsKey.region) ?? ""
        self.phoneNumberDisplayFormat = PhoneNumberService.displayFormat
        self.phoneNumberDialFormat = PhoneNumberService.dialFormat
        self.internationalPrefix = defaults.string(forKey: PhoneNumberSettingsKey.internationalPrefix) ?? ""
        self.formatAsYouType = PhoneNumberService.formatsAsYouType

        // Apply settings on init
        applyLogLevel()
        // The app follows the system appearance; clear any override saved by older versions
        defaults.removeObject(forKey: "settings.appearanceMode")
    }

    // MARK: - Actions

    /// Apply the current log level to TonePhoneCore.
    private func applyLogLevel() {
        TonePhoneCore.shared.setLogLevel(logLevel)
    }

    /// Apply diagnostics settings once the SIP engine is running.
    func applyCoreSettings() {
        applyLogLevel()
        TonePhoneCore.shared.setSIPTraceEnabled(advancedMode && sipTrace)
        TonePhoneCore.shared.setEchoCancellation(echoCancellation)
    }

    /// Engine options written to the config file at start.
    var coreOptions: CoreOptions {
        CoreOptions(verifyTLSServer: verifyTLSServer, additionalCAFile: additionalCAFile)
    }

    enum CertificateImportError: LocalizedError {
        case notPEM

        var errorDescription: String? {
            "The file doesn’t contain certificates in PEM format."
        }
        var recoverySuggestion: String? {
            "Choose a .pem or .crt file that starts with “-----BEGIN CERTIFICATE-----”."
        }
    }

    /// Copies a PEM certificate file into Application Support and trusts it
    /// for TLS from the next launch.
    func importAdditionalCertificates(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard String(decoding: data, as: UTF8.self).contains("-----BEGIN CERTIFICATE-----") else {
            throw CertificateImportError.notPEM
        }
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("TonePhone", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("trusted-certificates.pem")
        try data.write(to: destination, options: .atomic)
        additionalCAFile = destination.path
    }

    /// Stops trusting the imported certificates.
    func removeAdditionalCertificates() {
        if let path = additionalCAFile {
            try? FileManager.default.removeItem(atPath: path)
        }
        additionalCAFile = nil
    }

    /// Phone number settings changed; views that show numbers re-render.
    private func notifyPhoneNumberFormatChanged() {
        NotificationCenter.default.post(name: .phoneNumberFormatDidChange, object: nil)
    }

    /// Reset all settings to defaults.
    func resetToDefaults() {
        logLevel = LogLevel(rawValue: Defaults.logLevel) ?? .info
        defaultTransport = SIPTransport(rawValue: Defaults.defaultTransport) ?? .udp
        stunServer = Defaults.stunServer
        stunServers = Defaults.stunServers
        natMethod = NATMethod(rawValue: Defaults.natMethod) ?? .stun
        natPinhole = Defaults.natPinhole
        dtmfMode = DTMFMode(rawValue: Defaults.dtmfMode) ?? .rfc2833
        verifyTLSServer = Defaults.verifyTLSServer
        sipTrace = false
        registerOnStartup = Defaults.registerOnStartup
        selectedRingtone = Defaults.selectedRingtone
        phoneNumberRegion = ""
        phoneNumberDisplayFormat = .international
        phoneNumberDialFormat = .e164
        internationalPrefix = ""
        formatAsYouType = true
    }
}

extension Notification.Name {
    static let phoneNumberFormatDidChange = Notification.Name("com.tonephone.phoneNumberFormatDidChange")
}
