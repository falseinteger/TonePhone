//
//  SettingsStore.swift
//  TonePhone
//
//  Manages app settings persistence using UserDefaults.
//

import Foundation

/// DTMF transmission mode for SIP calls.
enum DTMFMode: String, Codable, CaseIterable {
    case rfc2833 = "rfc2833"
    case sipInfo = "info"
    case inband = "inband"

    var displayName: String {
        switch self {
        case .rfc2833: return "RFC 2833"
        case .sipInfo: return "SIP INFO"
        case .inband: return "In-band"
        }
    }

    var description: String {
        switch self {
        case .rfc2833: return "Send DTMF as RTP events (recommended)"
        case .sipInfo: return "Send DTMF via SIP INFO messages"
        case .inband: return "Send DTMF as audio tones"
        }
    }
}

/// NAT traversal method for media.
enum NATMethod: String, Codable, CaseIterable {
    case stun = "stun"
    case ice = "ice"
    case none = ""

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
        static let natMethod = "settings.natMethod"
        static let natPinhole = "settings.natPinhole"
        static let dtmfMode = "settings.dtmfMode"
        static let rtcpFeedback = "settings.rtcpFeedback"
        static let registerOnStartup = "settings.registerOnStartup"
    }

    // MARK: - Default Values

    private enum Defaults {
        static let logLevel = LogLevel.info.rawValue
        static let defaultTransport = "udp"
        static let stunServer = "stun:stun.l.google.com:19302"
        static let natMethod = "stun"
        static let natPinhole = true
        static let dtmfMode = "rfc2833"
        static let rtcpFeedback = true
        static let registerOnStartup = true
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

    /// STUN server address.
    @Published var stunServer: String {
        didSet {
            defaults.set(stunServer, forKey: Keys.stunServer)
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

    /// Enable RTCP feedback.
    @Published var rtcpFeedback: Bool {
        didSet {
            defaults.set(rtcpFeedback, forKey: Keys.rtcpFeedback)
        }
    }

    /// Auto-register accounts on app startup.
    @Published var registerOnStartup: Bool {
        didSet {
            defaults.set(registerOnStartup, forKey: Keys.registerOnStartup)
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

        if defaults.object(forKey: Keys.rtcpFeedback) != nil {
            self.rtcpFeedback = defaults.bool(forKey: Keys.rtcpFeedback)
        } else {
            self.rtcpFeedback = Defaults.rtcpFeedback
        }

        if defaults.object(forKey: Keys.registerOnStartup) != nil {
            self.registerOnStartup = defaults.bool(forKey: Keys.registerOnStartup)
        } else {
            self.registerOnStartup = Defaults.registerOnStartup
        }

        // Apply log level on init
        applyLogLevel()
    }

    // MARK: - Actions

    /// Apply the current log level to TonePhoneCore.
    private func applyLogLevel() {
        TonePhoneCore.shared.setLogLevel(logLevel)
    }

    /// Reset all settings to defaults.
    func resetToDefaults() {
        logLevel = .info
        defaultTransport = .udp
        stunServer = Defaults.stunServer
        natMethod = .stun
        natPinhole = Defaults.natPinhole
        dtmfMode = .rfc2833
        rtcpFeedback = Defaults.rtcpFeedback
        registerOnStartup = Defaults.registerOnStartup
    }
}
