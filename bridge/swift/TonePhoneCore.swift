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

        // Register event callback before init
        registerEventCallback()

        // Initialize bridge
        let initResult = tp_init(configPath, logPath)
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
            throw TonePhoneError(from: startResult)
        }
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
