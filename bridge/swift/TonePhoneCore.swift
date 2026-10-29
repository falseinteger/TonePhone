//
//  TonePhoneCore.swift
//  TonePhone
//
//  Swift wrapper for the TonePhone bridge C API.
//  Provides a clean Swift interface with Combine integration for events.
//

import Foundation
import Combine

// MARK: - Error Types

/// Errors that can occur when interacting with the TonePhone bridge.
public enum TonePhoneError: Error, Equatable {
    case invalidArgument
    case notInitialized
    case alreadyInitialized
    case notStarted
    case alreadyStarted
    case notFound
    case alreadyExists
    case noMemory
    case network
    case timeout
    case registrationFailed
    case callFailed
    case mediaFailed
    case internalError
    case unknown(UInt32)

    /// Initialize from C error code.
    init(from error: tp_error_t) {
        switch error {
        case TP_ERR_INVALID_ARG:
            self = .invalidArgument
        case TP_ERR_NOT_INITIALIZED:
            self = .notInitialized
        case TP_ERR_ALREADY_INITIALIZED:
            self = .alreadyInitialized
        case TP_ERR_NOT_STARTED:
            self = .notStarted
        case TP_ERR_ALREADY_STARTED:
            self = .alreadyStarted
        case TP_ERR_NOT_FOUND:
            self = .notFound
        case TP_ERR_ALREADY_EXISTS:
            self = .alreadyExists
        case TP_ERR_NO_MEMORY:
            self = .noMemory
        case TP_ERR_NETWORK:
            self = .network
        case TP_ERR_TIMEOUT:
            self = .timeout
        case TP_ERR_REGISTRATION_FAILED:
            self = .registrationFailed
        case TP_ERR_CALL_FAILED:
            self = .callFailed
        case TP_ERR_MEDIA_FAILED:
            self = .mediaFailed
        case TP_ERR_INTERNAL:
            self = .internalError
        default:
            self = .unknown(error.rawValue)
        }
    }

    /// Human-readable description.
    public var localizedDescription: String {
        switch self {
        case .invalidArgument:
            return "Invalid argument"
        case .notInitialized:
            return "Bridge not initialized"
        case .alreadyInitialized:
            return "Bridge already initialized"
        case .notStarted:
            return "Bridge not started"
        case .alreadyStarted:
            return "Bridge already started"
        case .notFound:
            return "Resource not found"
        case .alreadyExists:
            return "Resource already exists"
        case .noMemory:
            return "Memory allocation failed"
        case .network:
            return "Network error"
        case .timeout:
            return "Operation timed out"
        case .registrationFailed:
            return "SIP registration failed"
        case .callFailed:
            return "Call setup failed"
        case .mediaFailed:
            return "Media setup failed"
        case .internalError:
            return "Internal error"
        case .unknown(let code):
            return "Unknown error (\(code))"
        }
    }
}

// MARK: - State Types

/// Core engine state.
public enum CoreState: Equatable, Sendable {
    case idle
    case starting
    case running
    case stopping

    init(from state: tp_core_state_t) {
        switch state {
        case TP_CORE_STATE_IDLE:
            self = .idle
        case TP_CORE_STATE_STARTING:
            self = .starting
        case TP_CORE_STATE_RUNNING:
            self = .running
        case TP_CORE_STATE_STOPPING:
            self = .stopping
        default:
            self = .idle
        }
    }
}

/// Account registration state.
public enum AccountState: Equatable, Sendable {
    case unregistered
    case registering
    case registered
    case failed(reason: String?)

    init(from state: tp_account_state_t, reason: String?) {
        switch state {
        case TP_ACCOUNT_STATE_UNREGISTERED:
            self = .unregistered
        case TP_ACCOUNT_STATE_REGISTERING:
            self = .registering
        case TP_ACCOUNT_STATE_REGISTERED:
            self = .registered
        case TP_ACCOUNT_STATE_FAILED:
            self = .failed(reason: reason)
        default:
            self = .unregistered
        }
    }
}

/// Call state.
public enum CallState: Equatable, Sendable {
    case idle
    case outgoing
    case incoming(remoteURI: String?)
    case early
    case established
    case held
    case ended(reason: String?)

    init(from state: tp_call_state_t, remoteURI: String?, reason: String?) {
        switch state {
        case TP_CALL_STATE_IDLE:
            self = .idle
        case TP_CALL_STATE_OUTGOING:
            self = .outgoing
        case TP_CALL_STATE_INCOMING:
            self = .incoming(remoteURI: remoteURI)
        case TP_CALL_STATE_EARLY:
            self = .early
        case TP_CALL_STATE_ESTABLISHED:
            self = .established
        case TP_CALL_STATE_HELD:
            self = .held
        case TP_CALL_STATE_ENDED:
            self = .ended(reason: reason)
        default:
            self = .idle
        }
    }
}

/// Log level for filtering messages.
public enum LogLevel: Int, Sendable, CaseIterable {
    case error = 0
    case warning = 1
    case info = 2
    case debug = 3
    case trace = 4

    /// Convert to C log level.
    var cLevel: tp_log_level_t {
        switch self {
        case .error:   return TP_LOG_ERROR
        case .warning: return TP_LOG_WARNING
        case .info:    return TP_LOG_INFO
        case .debug:   return TP_LOG_DEBUG
        case .trace:   return TP_LOG_TRACE
        }
    }

    /// Initialize from C log level.
    init(from cLevel: tp_log_level_t) {
        switch cLevel {
        case TP_LOG_ERROR:   self = .error
        case TP_LOG_WARNING: self = .warning
        case TP_LOG_INFO:    self = .info
        case TP_LOG_DEBUG:   self = .debug
        case TP_LOG_TRACE:   self = .trace
        default:             self = .info
        }
    }

    /// Human-readable name.
    public var name: String {
        switch self {
        case .error:   return "Error"
        case .warning: return "Warning"
        case .info:    return "Info"
        case .debug:   return "Debug"
        case .trace:   return "Trace"
        }
    }
}

// MARK: - Audio Device Types

/// Type of audio device.
public enum AudioDeviceType: Sendable {
    case input   /// Microphone
    case output  /// Speaker
}

/// Represents an audio device (microphone or speaker).
public struct AudioDevice: Identifiable, Hashable, Sendable {
    /// Unique identifier for the device.
    public let id: String

    /// Human-readable device name.
    public let name: String

    /// Device type (input/output).
    public let type: AudioDeviceType

    /// Whether this is the system default device.
    public let isDefault: Bool

    /// Sentinel for "System Default" selection.
    public static func systemDefault(type: AudioDeviceType) -> AudioDevice {
        AudioDevice(
            id: "",
            name: "System Default",
            type: type,
            isDefault: false
        )
    }
}

// MARK: - ID Types

/// Opaque account identifier.
public struct AccountID: Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Invalid/unassigned ID.
    public static let invalid = AccountID(rawValue: 0)

    public var isValid: Bool {
        rawValue != 0
    }
}

/// Opaque call identifier.
public struct CallID: Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Invalid/unassigned ID.
    public static let invalid = CallID(rawValue: 0)

    public var isValid: Bool {
        rawValue != 0
    }
}

// MARK: - Events

/// Extra information delivered with every call state change.
public struct CallEventDetails: Sendable, Equatable {
    /// Remote display name from the SIP From/To header, if any.
    public let remoteName: String?
    /// Account that owns the call.
    public let accountID: AccountID
}

/// Events emitted by TonePhoneCore.
public enum TonePhoneEvent: Sendable {
    case coreStateChanged(CoreState)
    case accountStateChanged(AccountID, AccountState)
    case callStateChanged(CallID, CallState, CallEventDetails)
    case mediaChanged(CallID, audioEstablished: Bool, videoEstablished: Bool, encrypted: Bool)
    case audioDeviceChanged
    case messageWaiting(AccountID, VoicemailStatus)
}

/// Voicemail status from a message-summary notification (RFC 3842).
public struct VoicemailStatus: Sendable, Equatable {
    public var hasNewMessages: Bool
    /// New voice messages, nil when the server does not report a count.
    public var newMessages: Int?
    public var oldMessages: Int?

    public init(hasNewMessages: Bool, newMessages: Int? = nil, oldMessages: Int? = nil) {
        self.hasNewMessages = hasNewMessages
        self.newMessages = newMessages
        self.oldMessages = oldMessages
    }

    /// Parses `Messages-Waiting: yes` and `Voice-Message: 2/8 (0/0)`.
    public init(summary: String) {
        var waiting = false
        var new: Int?
        var old: Int?
        for line in summary.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch name {
            case "messages-waiting":
                waiting = value.lowercased() == "yes"
            case "voice-message":
                let counts = value.split(separator: " ").first?.split(separator: "/") ?? []
                if counts.count == 2 {
                    new = Int(counts[0])
                    old = Int(counts[1])
                }
            default:
                break
            }
        }
        self.init(hasNewMessages: waiting || (new ?? 0) > 0, newMessages: new, oldMessages: old)
    }
}

// MARK: - Account Configuration

/// Everything the SIP engine needs to create and register an account.
///
/// Optional strings are omitted from the account when nil or empty.
public struct AccountConfiguration: Sendable {
    /// Address of record, e.g. `sip:alice@example.com:5060`.
    public var sipURI: String
    public var password: String
    public var displayName: String?
    /// Authentication username when it differs from the URI user.
    public var authUsername: String?
    /// Outbound proxy URI, e.g. `sip:proxy.example.com;transport=tcp`.
    public var outboundProxy: String?
    /// `udp`, `tcp` or `tls`.
    public var transport: String?
    public var stunServer: String?
    /// `stun` or `ice`.
    public var mediaNAT: String?
    /// `srtp`, `srtp-mand` or `dtls_srtp`.
    public var mediaEncryption: String?
    /// `rtpevent`, `info` or `auto`.
    public var dtmfMode: String?
    /// Registration interval in seconds.
    public var registrationInterval: UInt32
    public var natPinhole: Bool
    /// Subscribe to voicemail notifications.
    public var voicemailNotifications: Bool
    public var registerImmediately: Bool

    public init(
        sipURI: String,
        password: String,
        displayName: String? = nil,
        authUsername: String? = nil,
        outboundProxy: String? = nil,
        transport: String? = nil,
        stunServer: String? = nil,
        mediaNAT: String? = nil,
        mediaEncryption: String? = nil,
        dtmfMode: String? = nil,
        registrationInterval: UInt32 = 3600,
        natPinhole: Bool = true,
        voicemailNotifications: Bool = false,
        registerImmediately: Bool = true
    ) {
        self.sipURI = sipURI
        self.password = password
        self.displayName = displayName
        self.authUsername = authUsername
        self.outboundProxy = outboundProxy
        self.transport = transport
        self.stunServer = stunServer
        self.mediaNAT = mediaNAT
        self.mediaEncryption = mediaEncryption
        self.dtmfMode = dtmfMode
        self.registrationInterval = registrationInterval
        self.natPinhole = natPinhole
        self.voicemailNotifications = voicemailNotifications
        self.registerImmediately = registerImmediately
    }
}

/// Engine-wide options written to the baresip config file at start.
public struct CoreOptions: Sendable {
    /// Verify the SIP server certificate for TLS connections.
    public var verifyTLSServer: Bool
    /// PEM file with extra certificate authorities to trust in addition to
    /// the system ones, e.g. a provider's private CA.
    public var additionalCAFile: String?

    public init(verifyTLSServer: Bool = true, additionalCAFile: String? = nil) {
        self.verifyTLSServer = verifyTLSServer
        self.additionalCAFile = additionalCAFile
    }
}

// MARK: - TonePhoneCore

/// Main interface to the TonePhone SIP engine.
///
/// Use `TonePhoneCore.shared` to access the singleton instance.
/// Call `start()` to initialize and begin network operations,
/// and `stop()` to shut down gracefully.
@MainActor
public final class TonePhoneCore {

    // MARK: - Singleton

    /// Shared singleton instance.
    public static let shared = TonePhoneCore()

    // MARK: - Properties

    /// Publisher for TonePhone events.
    /// Events are always delivered on the main thread.
    public var events: AnyPublisher<TonePhoneEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    /// Current core state.
    @Published public private(set) var coreState: CoreState = .idle

    // MARK: - Private Properties

    private let eventSubject = PassthroughSubject<TonePhoneEvent, Never>()
    private var isInitialized = false

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton
    }

    deinit {
        // Clean shutdown
        if isInitialized {
            tp_set_event_callback(nil, nil)
            tp_shutdown()
        }
    }

    // MARK: - Lifecycle

    /// Initialize and start the TonePhone engine.
    ///
    /// This initializes the underlying baresip engine and begins network operations.
    /// Events will be published via the `events` publisher.
    ///
    /// - Parameters:
    ///   - configPath: Optional path to configuration directory.
    ///   - logPath: Optional path to log file.
    /// - Throws: `TonePhoneError` if initialization or start fails.
    public func start(options: CoreOptions = CoreOptions(), configPath: String? = nil, logPath: String? = nil) throws {
        guard !isInitialized else {
            throw TonePhoneError.alreadyInitialized
        }

        // Ensure config directory exists with minimal config
        let effectiveConfigPath = try configPath ?? createDefaultConfigDirectory(options: options)

        // Ensure logs directory exists
        let effectiveLogPath = try logPath ?? createDefaultLogsDirectory()

        // Register event callback before init
        registerEventCallback()

        // Initialize bridge (includes file logging)
        let initResult = tp_init(effectiveConfigPath, effectiveLogPath)
        guard initResult == TP_OK else {
            tp_set_event_callback(nil, nil)
            throw TonePhoneError(from: initResult)
        }

        isInitialized = true

        // Start bridge
        let startResult = tp_start()
        guard startResult == TP_OK else {
            tp_set_event_callback(nil, nil)
            tp_shutdown()
            isInitialized = false
            coreState = .idle
            throw TonePhoneError(from: startResult)
        }
    }

    /// Creates the config directory and writes the baresip configuration.
    ///
    /// The file is owned by the app and rewritten on every launch, so fixes
    /// and new options reach existing installations.
    /// - Returns: Path to the config directory.
    private func createDefaultConfigDirectory(options: CoreOptions) throws -> String {
        let fileManager = FileManager.default

        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TonePhoneError.internalError
        }

        let configDir = appSupport.appendingPathComponent("TonePhone", isDirectory: true)
        try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)

        // macOS ships the system root certificates as a PEM bundle; OpenSSL
        // cannot read the Keychain, so point it at this file for TLS.
        var caFile = "/etc/ssl/cert.pem"
        if let extra = options.additionalCAFile, fileManager.fileExists(atPath: extra) {
            // OpenSSL takes one CA file: combine the system roots with the extra ones.
            // The config format ends a value at the first space, so the bundle
            // can't live under "Application Support"; the per-user temporary
            // directory has no spaces and the file is rewritten on every launch.
            let bundle = fileManager.temporaryDirectory.appendingPathComponent("tonephone-ca-bundle.pem")
            var data = (try? Data(contentsOf: URL(fileURLWithPath: caFile))) ?? Data()
            data.append(contentsOf: Array("\n".utf8))
            data.append((try? Data(contentsOf: URL(fileURLWithPath: extra))) ?? Data())
            if (try? data.write(to: bundle, options: .atomic)) != nil {
                caFile = bundle.path
            }
        }
        let tlsLines: String
        if fileManager.fileExists(atPath: caFile) {
            tlsLines = """
            sip_cafile \(caFile)
            sip_verify_server \(options.verifyTLSServer ? "yes" : "no")
            """
        } else {
            tlsLines = "sip_verify_server no"
        }

        let config = """
        # TonePhone configuration
        # Generated by TonePhone on every launch. Edits will be overwritten.

        #------------------------------------------------------------
        # Modules (statically linked)
        #------------------------------------------------------------
        module g711.so
        module opus.so
        module audiounit.so
        module stun.so
        module turn.so
        module ice.so
        module srtp.so
        module dtls_srtp.so
        module account.so
        module netroam.so
        module mwi.so

        #------------------------------------------------------------
        # Audio
        #------------------------------------------------------------
        audio_player audiounit
        audio_source audiounit
        audio_alert audiounit

        # Prefer Opus for quality, G.711 as fallback
        audio_codecs opus,g711

        #------------------------------------------------------------
        # SIP
        #------------------------------------------------------------
        sip_listen 0.0.0.0:0
        \(tlsLines)

        # Re-register when the network changes (Wi-Fi switch, VPN, wake)
        netroam_interval 10

        #------------------------------------------------------------
        # Calls
        #------------------------------------------------------------
        call_accept yes

        """

        let configFile = configDir.appendingPathComponent("config")
        try config.write(to: configFile, atomically: true, encoding: .utf8)

        return configDir.path
    }

    /// Creates a default logs directory.
    /// - Returns: Path to the created logs directory.
    private func createDefaultLogsDirectory() throws -> String {
        let fileManager = FileManager.default

        // Get Application Support directory
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TonePhoneError.internalError
        }

        let logsDir = appSupport
            .appendingPathComponent("TonePhone", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: logsDir.path) {
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }

        return logsDir.path
    }

    /// Stop and shut down the TonePhone engine.
    ///
    /// This stops all network operations, ends all calls, unregisters all accounts,
    /// and releases all resources. After calling this, `start()` can be called again.
    ///
    /// - Throws: `TonePhoneError` if stop fails.
    public func stop() throws {
        guard isInitialized else {
            throw TonePhoneError.notInitialized
        }

        let stopResult = tp_stop()
        if stopResult != TP_OK && stopResult != TP_ERR_NOT_STARTED {
            throw TonePhoneError(from: stopResult)
        }

        tp_set_event_callback(nil, nil)
        tp_shutdown()
        isInitialized = false
        coreState = .idle
    }

    // MARK: - Logging

    /// Set the minimum log level.
    ///
    /// Messages below this level are not written to the log file.
    /// Default is `.info`.
    ///
    /// - Parameter level: The minimum log level
    public func setLogLevel(_ level: LogLevel) {
        tp_log_set_level(level.cLevel)
    }

    /// Get the current log level.
    ///
    /// - Returns: The current minimum log level
    public func getLogLevel() -> LogLevel {
        LogLevel(from: tp_log_get_level())
    }

    /// Get the path to the current log file.
    ///
    /// - Returns: The log file path, or nil if logging is not initialized
    public func getLogFilePath() -> String? {
        var buffer = [CChar](repeating: 0, count: 512)
        let result = tp_log_get_path(&buffer, buffer.count)
        guard result == TP_OK else { return nil }
        return String(cString: buffer)
    }

    /// Enable or disable SIP message tracing in the log file.
    ///
    /// - Parameter enabled: When true, every SIP message is logged with
    ///   credentials redacted.
    public func setSIPTraceEnabled(_ enabled: Bool) {
        tp_log_set_sip_trace(enabled)
    }

    /// Use voice processing (echo cancellation, noise reduction) for calls
    /// that start from now on.
    public func setEchoCancellation(_ enabled: Bool) {
        tp_audio_set_echo_cancellation(enabled)
    }

    /// Write an app message to the TonePhone log.
    public nonisolated static func log(_ message: String, level: LogLevel = .info) {
        tp_log_message(level.cLevel, "app: " + message)
    }

    /// Flush log buffers to disk.
    ///
    /// Call this before exporting logs to ensure all messages are written.
    public func flushLogs() {
        tp_log_flush()
    }

    // MARK: - Account Management

    /// Add a new SIP account.
    ///
    /// - Parameter configuration: Account settings.
    /// - Returns: The account ID assigned to the new account
    /// - Throws: `TonePhoneError` if adding the account fails
    public func addAccount(_ configuration: AccountConfiguration) throws -> AccountID {
        // C strings must outlive the tp_account_add call; strdup and free after.
        var allocated: [UnsafeMutablePointer<CChar>] = []
        defer { allocated.forEach { free($0) } }

        func cString(_ value: String?) -> UnsafePointer<CChar>? {
            guard let value, !value.isEmpty, let copy = strdup(value) else { return nil }
            allocated.append(copy)
            return UnsafePointer(copy)
        }

        var config = tp_account_config_t()
        config.sip_uri = cString(configuration.sipURI)
        config.password = cString(configuration.password) ?? cString(" ")
        config.display_name = cString(configuration.displayName)
        config.auth_user = cString(configuration.authUsername)
        config.outbound_proxy = cString(configuration.outboundProxy)
        config.transport = cString(configuration.transport)
        config.stun_server = cString(configuration.stunServer)
        config.medianat = cString(configuration.mediaNAT)
        config.media_encryption = cString(configuration.mediaEncryption)
        config.dtmf_mode = cString(configuration.dtmfMode)
        config.reg_interval = configuration.registrationInterval
        config.nat_pinhole = configuration.natPinhole
        config.mwi = configuration.voicemailNotifications
        config.register_on_add = configuration.registerImmediately

        guard config.sip_uri != nil else {
            throw TonePhoneError.invalidArgument
        }

        var accountID: tp_account_id_t = TP_INVALID_ID
        let result = tp_account_add(&config, &accountID)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }

        return AccountID(rawValue: accountID)
    }

    /// Remove an account.
    ///
    /// - Parameter accountID: The account ID to remove
    /// - Throws: `TonePhoneError` if removal fails
    public func removeAccount(_ accountID: AccountID) throws {
        let result = tp_account_remove(accountID.rawValue)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Register an account with the SIP server.
    ///
    /// - Parameter accountID: The account ID to register
    /// - Throws: `TonePhoneError` if registration request fails
    public func registerAccount(_ accountID: AccountID) throws {
        let result = tp_account_register(accountID.rawValue)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Unregister an account from the SIP server.
    ///
    /// - Parameter accountID: The account ID to unregister
    /// - Throws: `TonePhoneError` if unregistration request fails
    public func unregisterAccount(_ accountID: AccountID) throws {
        let result = tp_account_unregister(accountID.rawValue)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Set the default account for outgoing calls.
    ///
    /// - Parameter accountID: The account ID to set as default
    /// - Throws: `TonePhoneError` if setting default fails
    public func setDefaultAccount(_ accountID: AccountID) throws {
        let result = tp_account_set_default(accountID.rawValue)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Get the current registration state of an account.
    ///
    /// - Parameter accountID: The account ID to query
    /// - Returns: The current account state
    /// - Throws: `TonePhoneError` if query fails
    public func getAccountState(_ accountID: AccountID) throws -> AccountState {
        var state: tp_account_state_t = TP_ACCOUNT_STATE_UNREGISTERED

        let result = tp_account_get_state(accountID.rawValue, &state)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }

        switch state {
        case TP_ACCOUNT_STATE_UNREGISTERED:
            return .unregistered
        case TP_ACCOUNT_STATE_REGISTERING:
            return .registering
        case TP_ACCOUNT_STATE_REGISTERED:
            return .registered
        case TP_ACCOUNT_STATE_FAILED:
            return .failed(reason: nil)
        default:
            return .unregistered
        }
    }

    /// Get the default account ID.
    ///
    /// - Returns: The default account ID, or nil if no default is set
    public func getDefaultAccount() -> AccountID? {
        var accountID: tp_account_id_t = TP_INVALID_ID

        let result = tp_account_get_default(&accountID)
        guard result == TP_OK, accountID != TP_INVALID_ID else {
            return nil
        }

        return AccountID(rawValue: accountID)
    }

    /// Get the number of configured accounts.
    ///
    /// - Returns: The number of active accounts
    public func accountCount() -> Int {
        return Int(tp_account_count())
    }

    /// Get all configured account IDs.
    ///
    /// - Returns: Array of account IDs
    public func getAllAccountIDs() -> [AccountID] {
        let count = tp_account_count()
        var ids: [AccountID] = []

        for i in 0..<count {
            var accountID: tp_account_id_t = TP_INVALID_ID
            if tp_account_get_id_at_index(i, &accountID) == TP_OK {
                ids.append(AccountID(rawValue: accountID))
            }
        }

        return ids
    }

    // MARK: - Call Control

    /// Start an outgoing call.
    ///
    /// - Parameter uri: The SIP URI to call (e.g., "sip:user@domain.com")
    /// - Returns: The call ID for the new call
    /// - Throws: `TonePhoneError` if call setup fails
    public func makeCall(to uri: String) throws -> CallID {
        var callID: tp_call_id_t = TP_INVALID_ID

        let result = uri.withCString { uriPtr in
            tp_call_start(uriPtr, &callID)
        }

        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }

        return CallID(rawValue: callID)
    }

    /// Answer an incoming call.
    ///
    /// - Parameter callID: The call ID to answer
    /// - Throws: `TonePhoneError` if answering fails
    public func answerCall(_ callID: CallID) throws {
        let result = tp_call_answer(callID.rawValue)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Hang up a call.
    ///
    /// - Parameter callID: The call ID to hang up
    /// - Throws: `TonePhoneError` if hangup fails
    public func hangupCall(_ callID: CallID) throws {
        let result = tp_call_hangup(callID.rawValue)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Hold or resume a call.
    ///
    /// - Parameters:
    ///   - callID: The call ID
    ///   - hold: `true` to hold, `false` to resume
    /// - Throws: `TonePhoneError` if hold/resume fails
    public func holdCall(_ callID: CallID, hold: Bool) throws {
        let result = tp_call_hold(callID.rawValue, hold)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Mute or unmute a call.
    ///
    /// - Parameters:
    ///   - callID: The call ID
    ///   - mute: `true` to mute, `false` to unmute
    /// - Throws: `TonePhoneError` if mute/unmute fails
    public func muteCall(_ callID: CallID, mute: Bool) throws {
        let result = tp_call_mute(callID.rawValue, mute)
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Send DTMF tones during a call.
    ///
    /// - Parameters:
    ///   - callID: The call ID
    ///   - digits: The DTMF digits to send (0-9, *, #, A-D)
    /// - Throws: `TonePhoneError` if sending DTMF fails
    public func sendDTMF(_ callID: CallID, digits: String) throws {
        let result = digits.withCString { digitsPtr in
            tp_call_send_dtmf(callID.rawValue, digitsPtr)
        }

        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    // MARK: - Audio Device Management

    /// Get list of available input devices (microphones).
    ///
    /// - Returns: Array of input devices, with system default devices marked.
    public func getInputDevices() -> [AudioDevice] {
        var list = tp_audio_device_list_t()
        let result = tp_audio_get_input_devices(&list)

        guard result == TP_OK else {
            return []
        }

        defer { tp_audio_device_list_free(&list) }

        var devices: [AudioDevice] = []
        for i in 0..<Int(list.count) {
            let dev = list.devices[i]
            let name = withUnsafePointer(to: dev.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            let uid = withUnsafePointer(to: dev.uid) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            devices.append(AudioDevice(
                id: uid,
                name: name,
                type: .input,
                isDefault: dev.is_default
            ))
        }

        return devices
    }

    /// Get list of available output devices (speakers).
    ///
    /// - Returns: Array of output devices, with system default devices marked.
    public func getOutputDevices() -> [AudioDevice] {
        var list = tp_audio_device_list_t()
        let result = tp_audio_get_output_devices(&list)

        guard result == TP_OK else {
            return []
        }

        defer { tp_audio_device_list_free(&list) }

        var devices: [AudioDevice] = []
        for i in 0..<Int(list.count) {
            let dev = list.devices[i]
            let name = withUnsafePointer(to: dev.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            let uid = withUnsafePointer(to: dev.uid) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            devices.append(AudioDevice(
                id: uid,
                name: name,
                type: .output,
                isDefault: dev.is_default
            ))
        }

        return devices
    }

    /// Get the currently selected input device name.
    ///
    /// - Returns: The device name, or nil if using system default.
    public func getCurrentInputDevice() -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        let result = tp_audio_get_current_input(&buffer, buffer.count)
        guard result == TP_OK else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// Get the currently selected output device name.
    ///
    /// - Returns: The device name, or nil if using system default.
    public func getCurrentOutputDevice() -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        let result = tp_audio_get_current_output(&buffer, buffer.count)
        guard result == TP_OK else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// Set the input device (microphone).
    ///
    /// - Parameter device: The device to use, or nil/empty name for system default.
    /// - Throws: `TonePhoneError` if setting fails.
    public func setInputDevice(_ device: AudioDevice?) throws {
        let deviceName = device?.name ?? ""
        let result: tp_error_t
        if deviceName.isEmpty || device?.id.isEmpty == true {
            result = tp_audio_set_input_device(nil)
        } else {
            result = deviceName.withCString { tp_audio_set_input_device($0) }
        }
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    /// Set the output device (speaker).
    ///
    /// - Parameter device: The device to use, or nil/empty name for system default.
    /// - Throws: `TonePhoneError` if setting fails.
    public func setOutputDevice(_ device: AudioDevice?) throws {
        let deviceName = device?.name ?? ""
        let result: tp_error_t
        if deviceName.isEmpty || device?.id.isEmpty == true {
            result = tp_audio_set_output_device(nil)
        } else {
            result = deviceName.withCString { tp_audio_set_output_device($0) }
        }
        guard result == TP_OK else {
            throw TonePhoneError(from: result)
        }
    }

    // MARK: - Event Handling

    private func registerEventCallback() {
        // Get unmanaged pointer to self for C callback context
        let context = Unmanaged.passUnretained(self).toOpaque()

        tp_set_event_callback({ event, ctx in
            guard let event = event, let ctx = ctx else { return }

            // Recover self from context
            let core = Unmanaged<TonePhoneCore>.fromOpaque(ctx).takeUnretainedValue()
            core.handleEvent(event.pointee)
        }, context)
    }

    /// Handle events from C callback (runs on baresip's event thread).
    /// Marked nonisolated to allow calling from non-main-actor context.
    private nonisolated func handleEvent(_ event: tp_event_t) {
        // Convert C event to Swift event (safe: String(cString:) copies data immediately)
        let swiftEvent: TonePhoneEvent
        var newCoreState: CoreState?

        switch event.type {
        case TP_EVENT_CORE_STATE_CHANGED:
            let state = CoreState(from: event.data.core.state)
            swiftEvent = .coreStateChanged(state)
            newCoreState = state

        case TP_EVENT_ACCOUNT_STATE_CHANGED:
            let accountID = AccountID(rawValue: event.data.account.id)
            let reason = event.data.account.reason.flatMap { String(cString: $0) }
            let state = AccountState(from: event.data.account.state, reason: reason)
            swiftEvent = .accountStateChanged(accountID, state)

        case TP_EVENT_CALL_STATE_CHANGED:
            let callID = CallID(rawValue: event.data.call.id)
            let remoteURI = event.data.call.remote_uri.flatMap { String(cString: $0) }
            let remoteName = event.data.call.remote_name.flatMap { String(cString: $0) }
            let reason = event.data.call.reason.flatMap { String(cString: $0) }
            let state = CallState(from: event.data.call.state, remoteURI: remoteURI, reason: reason)
            let details = CallEventDetails(
                remoteName: remoteName?.isEmpty == false ? remoteName : nil,
                accountID: AccountID(rawValue: event.data.call.account_id)
            )
            swiftEvent = .callStateChanged(callID, state, details)

        case TP_EVENT_CALL_MEDIA_CHANGED:
            let callID = CallID(rawValue: event.data.media.id)
            swiftEvent = .mediaChanged(
                callID,
                audioEstablished: event.data.media.audio_established,
                videoEstablished: event.data.media.video_established,
                encrypted: event.data.media.encrypted
            )

        case TP_EVENT_AUDIO_DEVICE_CHANGED:
            swiftEvent = .audioDeviceChanged

        case TP_EVENT_MESSAGE_WAITING:
            let summary = event.data.mwi.summary.flatMap { String(cString: $0) } ?? ""
            swiftEvent = .messageWaiting(
                AccountID(rawValue: event.data.mwi.account_id),
                VoicemailStatus(summary: summary)
            )

        default:
            // Ignore unhandled event types (log)
            return
        }

        // Hop to the main queue. DispatchQueue.main is FIFO, so events keep
        // the order the SIP stack produced them in (a Task per event does
        // not guarantee ordering).
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let state = newCoreState {
                    self.coreState = state
                }
                self.eventSubject.send(swiftEvent)
            }
        }
    }
}
