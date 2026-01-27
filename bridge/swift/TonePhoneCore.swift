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

/// Events emitted by TonePhoneCore.
public enum TonePhoneEvent: Sendable {
    case coreStateChanged(CoreState)
    case accountStateChanged(AccountID, AccountState)
    case callStateChanged(CallID, CallState)
    case mediaChanged(CallID, audioEstablished: Bool, videoEstablished: Bool, encrypted: Bool)
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
    public func start(configPath: String? = nil, logPath: String? = nil) throws {
        guard !isInitialized else {
            throw TonePhoneError.alreadyInitialized
        }

        // Ensure config directory exists with minimal config
        let effectiveConfigPath = try configPath ?? createDefaultConfigDirectory()

        // Ensure logs directory exists
        let effectiveLogPath = try logPath ?? createDefaultLogsDirectory()

        // Verify config file exists
        let configFile = URL(fileURLWithPath: effectiveConfigPath).appendingPathComponent("config")
        print("TonePhoneCore: Using config path: \(effectiveConfigPath)")
        print("TonePhoneCore: Config file exists: \(FileManager.default.fileExists(atPath: configFile.path))")
        print("TonePhoneCore: Using log path: \(effectiveLogPath)")

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

    /// Creates a default config directory with minimal baresip configuration.
    /// - Returns: Path to the created config directory.
    private func createDefaultConfigDirectory() throws -> String {
        let fileManager = FileManager.default

        // Get Application Support directory
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TonePhoneError.internalError
        }

        let configDir = appSupport.appendingPathComponent("TonePhone", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: configDir.path) {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        // Create minimal config file if it doesn't exist
        let configFile = configDir.appendingPathComponent("config")
        if !fileManager.fileExists(atPath: configFile.path) {
            // Minimal config for statically-linked baresip
            // Module lines are required to load static modules
            let minimalConfig = """
            # TonePhone configuration
            # Audio-only SIP client - video modules are not included

            #------------------------------------------------------------
            # Modules (statically linked, .so extension is optional)
            #------------------------------------------------------------
            # Audio codecs
            module g711.so
            module opus.so

            # Audio I/O (macOS/iOS native)
            module audiounit.so

            # NAT traversal
            module stun.so
            module turn.so
            module ice.so

            # Security (SRTP media encryption)
            module srtp.so
            module dtls_srtp.so

            # Account management
            module account.so

            #------------------------------------------------------------
            # Audio settings
            #------------------------------------------------------------
            audio_player audiounit
            audio_source audiounit
            audio_alert audiounit

            # Codec priority (prefer Opus for quality, G.711 as fallback)
            audio_codecs opus,g711

            #------------------------------------------------------------
            # SIP settings
            #------------------------------------------------------------
            sip_listen 0.0.0.0:0

            #------------------------------------------------------------
            # Call settings
            #------------------------------------------------------------
            # Accept incoming calls (required for incoming call handling)
            call_accept yes

            """
            try minimalConfig.write(to: configFile, atomically: true, encoding: .utf8)
        }

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

    /// Flush log buffers to disk.
    ///
    /// Call this before exporting logs to ensure all messages are written.
    public func flushLogs() {
        tp_log_flush()
    }

    // MARK: - Account Management

    /// Add a new SIP account.
    ///
    /// - Parameters:
    ///   - sipURI: The SIP URI (e.g., "sip:user@domain.com")
    ///   - password: The SIP password
    ///   - displayName: Optional display name
    ///   - transport: Transport protocol ("udp", "tcp", or "tls")
    ///   - stunServer: STUN server for NAT traversal (defaults to Google's STUN server)
    ///   - medianat: NAT traversal method (defaults to "ice")
    ///   - natPinhole: Enable NAT pinhole keep-alive (defaults to true for better NAT traversal)
    ///   - registerImmediately: Whether to register immediately after adding
    /// - Returns: The account ID assigned to the new account
    /// - Throws: `TonePhoneError` if adding the account fails
    public func addAccount(
        sipURI: String,
        password: String,
        displayName: String? = nil,
        transport: String? = nil,
        stunServer: String? = "stun:stun.l.google.com:19302",
        medianat: String? = "ice",
        natPinhole: Bool = true,
        registerImmediately: Bool = true
    ) throws -> AccountID {
        // Collect all optional strings that need to live through the C call
        let optionalStrings: [(String?, (inout tp_account_config_t, UnsafePointer<CChar>) -> Void)] = [
            (displayName, { cfg, ptr in cfg.display_name = ptr }),
            (transport, { cfg, ptr in cfg.transport = ptr }),
            (stunServer, { cfg, ptr in cfg.stun_server = ptr }),
            (medianat, { cfg, ptr in cfg.medianat = ptr }),
        ]

        return try sipURI.withCString { sipURIPtr in
            try password.withCString { passwordPtr in
                var config = tp_account_config_t()
                config.sip_uri = sipURIPtr
                config.password = passwordPtr
                config.register_on_add = registerImmediately
                config.nat_pinhole = natPinhole
                config.display_name = nil
                config.auth_user = nil
                config.outbound_proxy = nil
                config.transport = nil
                config.stun_server = nil
                config.medianat = nil

                return try withOptionalCStrings(optionalStrings, config: &config)
            }
        }
    }

    /// Helper to recursively handle optional C strings for account config.
    private func withOptionalCStrings(
        _ pairs: [(String?, (inout tp_account_config_t, UnsafePointer<CChar>) -> Void)],
        config: inout tp_account_config_t
    ) throws -> AccountID {
        guard let (value, setter) = pairs.first else {
            // Base case: all strings processed, make the C call
            return try addAccountWithConfig(&config)
        }

        let remaining = Array(pairs.dropFirst())

        if let value = value {
            return try value.withCString { ptr in
                setter(&config, ptr)
                return try withOptionalCStrings(remaining, config: &config)
            }
        } else {
            return try withOptionalCStrings(remaining, config: &config)
        }
    }

    private func addAccountWithConfig(_ config: inout tp_account_config_t) throws -> AccountID {
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
            let reason = event.data.call.reason.flatMap { String(cString: $0) }
            let state = CallState(from: event.data.call.state, remoteURI: remoteURI, reason: reason)
            swiftEvent = .callStateChanged(callID, state)

        case TP_EVENT_CALL_MEDIA_CHANGED:
            let callID = CallID(rawValue: event.data.media.id)
            swiftEvent = .mediaChanged(
                callID,
                audioEstablished: event.data.media.audio_established,
                videoEstablished: event.data.media.video_established,
                encrypted: event.data.media.encrypted
            )

        default:
            // Ignore unhandled event types (log, audio device)
            return
        }

        // Dispatch to main actor for state updates and event publishing
        Task { @MainActor in
            if let state = newCoreState {
                self.coreState = state
            }
            self.eventSubject.send(swiftEvent)
        }
    }
}
