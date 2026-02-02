//
//  AppViewModel.swift
//  TonePhone
//
//  View model for the main application state.
//  Subscribes to TonePhoneCore events and tracks account registration status.
//

import SwiftUI
import Combine
import AVFoundation

/// Simplified registration status for UI display.
///
/// Aggregates multiple account states into a single status for the main window.
enum RegistrationStatus: Equatable {
    /// No SIP accounts have been configured.
    case notConfigured
    /// At least one account is currently registering.
    case registering
    /// At least one account is successfully registered.
    case registered
    /// All accounts have failed to register.
    case failed(reason: String?)

    /// Human-readable text for display in the UI.
    var displayText: String {
        switch self {
        case .notConfigured:
            return "Not configured"
        case .registering:
            return "Registering..."
        case .registered:
            return "Registered"
        case .failed(let reason):
            if let reason = reason {
                return "Failed: \(reason)"
            }
            return "Registration failed"
        }
    }

    /// Color for the status indicator circle.
    var indicatorColor: Color {
        switch self {
        case .notConfigured:
            return .gray
        case .registering:
            return .orange
        case .registered:
            return .green
        case .failed:
            return .red
        }
    }
}

/// Represents the current screen in the app flow.
enum AppScreen: Equatable {
    /// Loading/connecting screen during auto-login.
    case connecting
    /// Account selection/list screen.
    case accountList
    /// Connected to an account, showing main interface.
    case activeAccount
    /// Active call in progress.
    case activeCall
}

/// Simplified call state for UI display.
enum UICallState: Equatable {
    case idle
    case outgoing
    case incoming(remoteURI: String?)
    case early
    case established
    case held
    case ended(reason: String?)
}

/// Main view model for tracking application state.
///
/// Subscribes to `TonePhoneCore.events` and maintains a map of account states.
/// Publishes an aggregated `registrationStatus` for the UI to display.
/// Also manages account configuration and persistence.
@MainActor
final class AppViewModel: ObservableObject {
    /// Current screen being displayed.
    @Published private(set) var currentScreen: AppScreen = .accountList

    /// Current registration status for display.
    @Published private(set) var registrationStatus: RegistrationStatus = .notConfigured

    /// Currently configured accounts.
    @Published private(set) var accounts: [SIPAccount] = []

    /// The currently selected account for editing.
    @Published var selectedAccount: SIPAccount?

    /// Whether the account configuration sheet is showing.
    @Published var isAccountSheetPresented = false

    /// Whether the connection progress sheet is showing.
    @Published var isConnectionSheetPresented = false

    /// The account currently being connected.
    @Published private(set) var connectingAccount: SIPAccount?

    /// The active (connected) account.
    @Published private(set) var activeAccount: SIPAccount?

    /// Error message to display to user.
    @Published var errorMessage: String?

    // MARK: - Call State

    /// Information about an active call.
    struct CallInfo {
        let id: CallID
        var state: UICallState
        var remoteURI: String?
        var remoteName: String?
        var isMuted: Bool = false
        var isOnHold: Bool = false
        var startTime: Date?
        var isOutgoing: Bool = false
    }

    /// All active calls tracked by ID.
    @Published private(set) var activeCalls: [CallID: CallInfo] = [:]

    // MARK: - Audio Device State

    /// Available input devices (microphones).
    @Published private(set) var inputDevices: [AudioDevice] = []

    /// Available output devices (speakers).
    @Published private(set) var outputDevices: [AudioDevice] = []

    /// Currently selected input device (nil = system default).
    @Published private(set) var selectedInputDevice: AudioDevice?

    /// Currently selected output device (nil = system default).
    @Published private(set) var selectedOutputDevice: AudioDevice?

    /// Current call state for UI display (for the selected call).
    @Published private(set) var callState: UICallState = .idle

    /// Active call ID (the currently selected/displayed call).
    @Published private(set) var activeCallID: CallID?

    /// Remote party URI for the current call.
    @Published private(set) var remotePartyURI: String?

    /// Remote party display name (parsed from URI or provided).
    @Published private(set) var remotePartyName: String?

    /// Whether the current call is muted.
    @Published private(set) var isMuted = false

    /// Whether the current call is on hold.
    @Published private(set) var isOnHold = false

    /// Call duration in seconds.
    @Published private(set) var callDuration: TimeInterval = 0

    /// Formatted call duration string (MM:SS or HH:MM:SS).
    var callDurationFormatted: String {
        let hours = Int(callDuration) / 3600
        let minutes = (Int(callDuration) % 3600) / 60
        let seconds = Int(callDuration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Timer for updating call duration.
    private var callDurationTimer: Timer?

    /// Call start time for duration calculation.
    private var callStartTime: Date?

    /// Pending cleanup work item to prevent stale timers affecting new calls.
    private var pendingCleanupWorkItem: DispatchWorkItem?

    /// Tracked account states by ID.
    private var accountStates: [AccountID: AccountState] = [:]

    /// Mapping from SIPAccount UUID to bridge AccountID.
    private var accountIDMapping: [UUID: AccountID] = [:]

    /// Combine cancellables for event subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Creates the view model and subscribes to TonePhoneCore events.
    init() {
        subscribeToEvents()
        startCore()
        loadAccounts()
        loadAudioDevicePreferences()
        setupIncomingCallManager()
        autoConnectIfNeeded()
        showAddAccountIfEmpty()
    }

    /// Sets up the incoming call manager callbacks.
    private func setupIncomingCallManager() {
        let callManager = IncomingCallManager.shared
        callManager.requestNotificationPermission()

        callManager.onAnswer = { [weak self] in
            self?.answerCall()
        }

        callManager.onDecline = { [weak self] in
            self?.hangupCall()
        }
    }

    /// Shows the add account sheet if no accounts exist.
    private func showAddAccountIfEmpty() {
        if accounts.isEmpty {
            // Delay slightly to ensure the UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showAddAccountSheet()
            }
        }
    }

    /// Starts the TonePhoneCore SIP engine.
    private func startCore() {
        do {
            try TonePhoneCore.shared.start()
            print("AppViewModel: TonePhoneCore started successfully")
        } catch {
            print("AppViewModel: Failed to start TonePhoneCore: \(error)")
            errorMessage = "Failed to initialize SIP engine: \(error.localizedDescription)"
        }
    }

    /// Subscribes to TonePhoneCore events to track account state changes.
    private func subscribeToEvents() {
        TonePhoneCore.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .accountSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, let accountID = notification.object as? UUID else { return }
                self.reregisterAccount(id: accountID)
            }
            .store(in: &cancellables)
    }

    /// Re-registers an account after its settings changed.
    private func reregisterAccount(id: UUID) {
        loadAccounts()
        guard let account = accounts.first(where: { $0.id == id }),
              let password = AccountStore.shared.getPassword(for: id) else { return }
        registerAccountWithCore(account, password: password)
    }

    /// Handles incoming events from TonePhoneCore.
    /// - Parameter event: The event to process.
    private func handleEvent(_ event: TonePhoneEvent) {
        switch event {
        case .accountStateChanged(let accountID, let state):
            accountStates[accountID] = state
            updateRegistrationStatus()

            // Handle connection completion - only for the account we're connecting
            if let connectingAccount,
               let connectingBridgeID = accountIDMapping[connectingAccount.id],
               connectingBridgeID == accountID {
                switch state {
                case .registered:
                    // Auto-complete connection when registered
                    if isConnectionSheetPresented {
                        completeConnection()
                    } else if currentScreen == .connecting {
                        // Auto-login flow: transition directly to active account
                        completeConnection()
                    }
                case .failed(let reason):
                    // Auto-login failed: go to account list and show error
                    if currentScreen == .connecting {
                        let accountName = connectingAccount.displayName.isEmpty == false
                            ? connectingAccount.displayName
                            : connectingAccount.username
                        errorMessage = "Failed to connect to \(accountName): \(reason ?? "Connection failed")"
                        self.connectingAccount = nil
                        currentScreen = .accountList
                    }
                default:
                    break
                }
            }

        case .callStateChanged(let callID, let state):
            handleCallStateChanged(callID: callID, state: state)

        case .audioDeviceChanged:
            handleAudioDeviceChanged()

        case .coreStateChanged, .mediaChanged:
            // Handled elsewhere or not needed for registration status
            break
        }
    }

    /// Handles call state changes from TonePhoneCore.
    private func handleCallStateChanged(callID: CallID, state: CallState) {
        // Update call in activeCalls dictionary
        var callInfo = activeCalls[callID] ?? CallInfo(id: callID, state: .idle)

        switch state {
        case .idle:
            // Remove from active calls
            activeCalls.removeValue(forKey: callID)
            // Ensure ringtone and notification are stopped
            IncomingCallManager.shared.handleCallEnded()
            // If this was the displayed call, switch to another or clear
            if activeCallID == callID {
                switchToNextCallOrClear()
            }

        case .outgoing:
            callInfo.state = .outgoing
            callInfo.isOutgoing = true
            activeCalls[callID] = callInfo
            // Make this the displayed call
            activeCallID = callID
            remotePartyURI = callInfo.remoteURI
            remotePartyName = callInfo.remoteName
            callState = .outgoing
            currentScreen = .activeCall

        case .incoming(let remoteURI):
            callInfo.state = .incoming(remoteURI: remoteURI)
            callInfo.remoteURI = remoteURI
            callInfo.remoteName = parseDisplayName(from: remoteURI)
            activeCalls[callID] = callInfo
            // Make this the displayed call
            activeCallID = callID
            remotePartyURI = remoteURI
            remotePartyName = callInfo.remoteName
            callState = .incoming(remoteURI: remoteURI)
            currentScreen = .activeCall

            // Trigger incoming call alert (ringtone, notification, bring to front)
            IncomingCallManager.shared.handleIncomingCall(
                callerName: remotePartyName,
                callerURI: remoteURI
            )

        case .early:
            callInfo.state = .early
            activeCalls[callID] = callInfo
            if activeCallID == callID {
                callState = .early
            }

        case .established:
            callInfo.state = .established
            callInfo.isOnHold = false
            callInfo.startTime = Date()
            activeCalls[callID] = callInfo
            if activeCallID == callID {
                callState = .established
                isOnHold = false
                startCallDurationTimer()
            }
            // Stop ringtone when call is answered
            IncomingCallManager.shared.handleCallEnded()

        case .held:
            callInfo.state = .held
            callInfo.isOnHold = true
            activeCalls[callID] = callInfo
            if activeCallID == callID {
                callState = .held
                isOnHold = true
            }

        case .ended(let reason):
            callInfo.state = .ended(reason: reason)
            activeCalls[callID] = callInfo
            // Stop ringtone and remove notification
            IncomingCallManager.shared.handleCallEnded()
            if activeCallID == callID {
                callState = .ended(reason: reason)
                stopCallDurationTimer()
            }
            scheduleCallCleanup(callID: callID, delay: 1.5)
        }
    }

    /// Switches to the next available call or clears call state if none.
    private func switchToNextCallOrClear() {
        // Find another call to display (prefer established, then held, then any)
        let nextCall = activeCalls.values.first { call in
            if case .established = call.state { return true }
            return false
        } ?? activeCalls.values.first { call in
            if case .held = call.state { return true }
            return false
        } ?? activeCalls.values.first { call in
            if case .incoming = call.state { return true }
            return false
        }

        if let nextCall = nextCall {
            // Switch to this call
            activeCallID = nextCall.id
            remotePartyURI = nextCall.remoteURI
            remotePartyName = nextCall.remoteName
            callState = nextCall.state
            isMuted = nextCall.isMuted
            isOnHold = nextCall.isOnHold
        } else {
            // No more calls, clear state
            clearCallState()
            if activeAccount != nil {
                currentScreen = .activeAccount
            } else {
                currentScreen = .accountList
            }
        }
    }

    /// Clears all call-related state.
    private func clearCallState() {
        activeCallID = nil
        remotePartyURI = nil
        remotePartyName = nil
        isMuted = false
        isOnHold = false
        callDuration = 0
        callStartTime = nil
        callState = .idle
        stopCallDurationTimer()
        cancelPendingCleanup()
    }

    /// Schedules cleanup after call ends.
    /// - Parameters:
    ///   - callID: The call ID that ended
    ///   - delay: Delay before cleanup runs
    private func scheduleCallCleanup(callID: CallID, delay: TimeInterval = 1.0) {
        // Cancel any existing cleanup first
        cancelPendingCleanup()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Clear the reference to avoid stale state
            self.pendingCleanupWorkItem = nil

            // Remove the ended call from tracking
            self.activeCalls.removeValue(forKey: callID)

            // If this was the displayed call, switch to another or clear
            if self.activeCallID == callID {
                self.switchToNextCallOrClear()
            }
        }

        // Store reference so it can be cancelled
        pendingCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancels any pending cleanup work item.
    private func cancelPendingCleanup() {
        pendingCleanupWorkItem?.cancel()
        pendingCleanupWorkItem = nil
    }

    /// Parses a display name from a SIP URI.
    private func parseDisplayName(from uri: String?) -> String? {
        guard let uri = uri else { return nil }

        // Try to extract display name from "Display Name" <sip:user@domain> format
        if let range = uri.range(of: "\"([^\"]+)\"", options: .regularExpression) {
            return String(uri[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        // Extract user part from sip:user@domain
        if uri.hasPrefix("sip:") {
            let withoutScheme = String(uri.dropFirst(4))
            if let atIndex = withoutScheme.firstIndex(of: "@") {
                return String(withoutScheme[..<atIndex])
            }
            return withoutScheme
        }

        return uri
    }

    /// Starts the call duration timer.
    private func startCallDurationTimer() {
        callStartTime = Date()
        callDuration = 0
        callDurationTimer?.invalidate()
        callDurationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.callStartTime else { return }
                self.callDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    /// Stops the call duration timer.
    private func stopCallDurationTimer() {
        callDurationTimer?.invalidate()
        callDurationTimer = nil
    }

    /// Recalculates the aggregated registration status from all account states.
    ///
    /// Priority order:
    /// 1. If any account is registered → `.registered`
    /// 2. If any account is registering → `.registering`
    /// 3. If any account failed → `.failed` with first error reason
    /// 4. Otherwise → `.notConfigured`
    private func updateRegistrationStatus() {
        // If no accounts, show not configured
        guard !accountStates.isEmpty else {
            registrationStatus = .notConfigured
            return
        }

        var hasRegistered = false
        var hasRegistering = false
        var firstFailureReason: String?

        for (_, state) in accountStates {
            switch state {
            case .registered:
                hasRegistered = true
            case .registering:
                hasRegistering = true
            case .failed(let reason):
                if firstFailureReason == nil {
                    firstFailureReason = reason
                }
            case .unregistered:
                break
            }
        }

        if hasRegistered {
            registrationStatus = .registered
        } else if hasRegistering {
            registrationStatus = .registering
        } else if let reason = firstFailureReason {
            registrationStatus = .failed(reason: reason)
        } else if accountStates.values.contains(where: { if case .failed = $0 { return true } else { return false } }) {
            registrationStatus = .failed(reason: nil)
        } else {
            registrationStatus = .notConfigured
        }
    }

    // MARK: - Account Management

    /// Loads accounts from persistent storage.
    private func loadAccounts() {
        accounts = AccountStore.shared.loadAccounts()
        updateRegistrationStatus()
    }

    /// Auto-connects to an account if autoLogin is enabled.
    private func autoConnectIfNeeded() {
        // Find account with autoLogin enabled
        guard let autoLoginAccount = accounts.first(where: { $0.autoLogin }) else {
            return
        }

        // Show connecting screen and start registration
        print("AppViewModel: Auto-connecting to \(autoLoginAccount.server)")
        connectingAccount = autoLoginAccount
        currentScreen = .connecting

        // Start registration
        if let password = AccountStore.shared.getPassword(for: autoLoginAccount.id) {
            registerAccountWithCore(autoLoginAccount, password: password)
        } else {
            // Password missing - show error and go to account list
            let accountName = autoLoginAccount.displayName.isEmpty ? autoLoginAccount.username : autoLoginAccount.displayName
            errorMessage = "Password missing for \(accountName). Please edit the account."
            connectingAccount = nil
            currentScreen = .accountList
        }
    }

    /// Shows the account configuration sheet for adding a new account.
    func showAddAccountSheet() {
        selectedAccount = nil
        isAccountSheetPresented = true
    }

    /// Shows the account configuration sheet for editing an existing account.
    /// - Parameter account: The account to edit.
    func showEditAccountSheet(for account: SIPAccount) {
        selectedAccount = account
        isAccountSheetPresented = true
    }

    /// Saves an account and triggers registration.
    /// - Parameters:
    ///   - account: The account configuration to save.
    ///   - password: The account password.
    func saveAccount(_ account: SIPAccount, password: String) {
        // Save to persistent storage
        AccountStore.shared.saveAccount(account)
        AccountStore.shared.savePassword(password, for: account.id)

        // Reload accounts list
        loadAccounts()

        // Register with TonePhoneCore
        registerAccountWithCore(account, password: password)
    }

    /// Deletes an account.
    /// - Parameter accountID: The UUID of the account to delete.
    func deleteAccount(id: UUID) {
        // Unregister from core if registered
        if let bridgeID = accountIDMapping[id] {
            do {
                try TonePhoneCore.shared.removeAccount(bridgeID)
            } catch {
                errorMessage = "Failed to remove account: \(error.localizedDescription)"
                print("Failed to remove account from core: \(error)")
                return
            }
            accountIDMapping.removeValue(forKey: id)
            accountStates.removeValue(forKey: bridgeID)
        }

        // Remove from persistent storage
        AccountStore.shared.deleteAccount(id: id)

        // Reload accounts list
        loadAccounts()
    }

    /// Registers an account with TonePhoneCore.
    /// - Parameters:
    ///   - account: The account to register.
    ///   - password: The account password.
    private func registerAccountWithCore(_ account: SIPAccount, password: String) {
        // Remove existing registration if present
        if let existingBridgeID = accountIDMapping[account.id] {
            do {
                try TonePhoneCore.shared.removeAccount(existingBridgeID)
                accountStates.removeValue(forKey: existingBridgeID)
                accountIDMapping.removeValue(forKey: account.id)
            } catch {
                errorMessage = "Failed to update account: \(error.localizedDescription)"
                print("Failed to remove existing account: \(error)")
                return
            }
        }

        // Resolve per-account overrides, falling back to global settings
        let settings = SettingsStore.shared
        let resolvedStunServer = account.stunServerOverride ?? settings.stunServer
        let resolvedNatMethod = account.natMethodOverride ?? settings.natMethod
        let resolvedNatPinhole = account.natPinholeOverride ?? settings.natPinhole

        let stunServer = resolvedStunServer.isEmpty ? nil : resolvedStunServer
        let medianat = resolvedNatMethod == .none ? nil : resolvedNatMethod.rawValue

        // Add new account to core
        do {
            let bridgeID = try TonePhoneCore.shared.addAccount(
                sipURI: account.sipURI,
                password: password,
                displayName: account.displayName.isEmpty ? nil : account.displayName,
                transport: account.transport.rawValue,
                stunServer: stunServer,
                medianat: medianat,
                natPinhole: resolvedNatPinhole,
                registerImmediately: true
            )
            accountIDMapping[account.id] = bridgeID
            accountStates[bridgeID] = .registering
            updateRegistrationStatus()
        } catch {
            errorMessage = "Failed to register account: \(error.localizedDescription)"
            print("Failed to add account to core: \(error)")
        }
    }

    /// Registers stored accounts that have passwords with TonePhoneCore.
    /// Available for batch registration if needed (e.g., after core restart).
    /// Note: Not called at startup; the app uses lazy registration via `startConnection`.
    /// Accounts without stored passwords are skipped.
    func registerStoredAccounts() {
        for account in accounts {
            if let password = AccountStore.shared.getPassword(for: account.id) {
                registerAccountWithCore(account, password: password)
            }
        }
    }

    // MARK: - Connection Flow

    /// Starts the connection process for an account.
    /// Shows the connection progress sheet.
    func startConnection(for account: SIPAccount) {
        connectingAccount = account
        isConnectionSheetPresented = true

        // Start registration
        if let password = AccountStore.shared.getPassword(for: account.id) {
            registerAccountWithCore(account, password: password)
        } else {
            // Password missing - show error and close sheet
            let accountName = account.displayName.isEmpty ? account.username : account.displayName
            errorMessage = "Password missing for \(accountName). Please edit the account."
            connectingAccount = nil
            isConnectionSheetPresented = false
            updateRegistrationStatus()
        }
    }

    /// Cancels the current connection attempt.
    func cancelConnection() {
        if let account = connectingAccount, let bridgeID = accountIDMapping[account.id] {
            do {
                try TonePhoneCore.shared.unregisterAccount(bridgeID)
            } catch {
                // Ignore errors when canceling
            }
            accountStates[bridgeID] = .unregistered
        }

        connectingAccount = nil
        isConnectionSheetPresented = false
        updateRegistrationStatus()
    }

    /// Cancels auto-connect and goes to account list.
    func cancelAutoConnect() {
        if let account = connectingAccount, let bridgeID = accountIDMapping[account.id] {
            do {
                try TonePhoneCore.shared.unregisterAccount(bridgeID)
            } catch {
                // Ignore errors when canceling
            }
            accountStates[bridgeID] = .unregistered
        }

        connectingAccount = nil
        currentScreen = .accountList
        updateRegistrationStatus()
    }

    /// Retries the connection for the current account.
    func retryConnection() {
        guard let account = connectingAccount else { return }

        if let password = AccountStore.shared.getPassword(for: account.id) {
            registerAccountWithCore(account, password: password)
        } else {
            errorMessage = "Password missing for \(account.username). Please edit the account."
        }
    }

    /// Opens the account editor for the connecting account.
    func editConnectingAccount() {
        guard let account = connectingAccount else { return }

        // Close connection sheet and open edit sheet
        isConnectionSheetPresented = false
        connectingAccount = nil
        showEditAccountSheet(for: account)
    }

    /// Completes the connection and transitions to active account screen.
    func completeConnection() {
        activeAccount = connectingAccount
        connectingAccount = nil
        isConnectionSheetPresented = false
        currentScreen = .activeAccount
    }

    /// Unregisters the active account and returns to account list.
    func unregisterAndGoBack() {
        if let account = activeAccount, let bridgeID = accountIDMapping[account.id] {
            do {
                try TonePhoneCore.shared.unregisterAccount(bridgeID)
            } catch {
                errorMessage = "Failed to unregister: \(error.localizedDescription)"
            }
            accountStates[bridgeID] = .unregistered
        }

        activeAccount = nil
        currentScreen = .accountList
        updateRegistrationStatus()
    }

    // MARK: - Call Control

    /// Puts all active (non-held, established) calls on hold.
    /// Call this before making or answering a new call.
    private func holdAllActiveCalls() {
        print("AppViewModel: holdAllActiveCalls called, activeCalls count: \(activeCalls.count)")
        // Iterate over a snapshot to avoid mutating while iterating
        let callsSnapshot = activeCalls
        for (callID, callInfo) in callsSnapshot {
            print("AppViewModel: Checking call \(callID), state: \(callInfo.state), isOnHold: \(callInfo.isOnHold)")
            // Only hold calls that are established and not already on hold
            if case .established = callInfo.state, !callInfo.isOnHold {
                do {
                    try TonePhoneCore.shared.holdCall(callID, hold: true)
                    var updatedInfo = callInfo
                    updatedInfo.isOnHold = true
                    updatedInfo.state = .held
                    activeCalls[callID] = updatedInfo
                    print("AppViewModel: Put call \(callID) on hold")
                } catch {
                    print("AppViewModel: Failed to hold call \(callID): \(error)")
                }
            }
        }
    }

    // MARK: - Microphone Permission

    /// Checks if microphone access is authorized.
    private func checkMicrophonePermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Requests microphone permission and calls completion with result.
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// Shows an error message about microphone permission.
    private func showMicrophonePermissionError() {
        errorMessage = "Microphone access is required for calls. Please enable it in System Settings > Privacy & Security > Microphone."
    }

    /// Makes an outgoing call to the specified URI.
    /// - Parameter uri: The SIP URI to call.
    func makeCall(to uri: String) {
        // Check microphone permission first
        requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }

            if !granted {
                self.showMicrophonePermissionError()
                return
            }

            // Cancel any pending cleanup from a previous call
            self.cancelPendingCleanup()

            // Put any active calls on hold first
            self.holdAllActiveCalls()

            do {
                let callID = try TonePhoneCore.shared.makeCall(to: uri)

                // Track the new call
                let callInfo = CallInfo(
                    id: callID,
                    state: .outgoing,
                    remoteURI: uri,
                    remoteName: self.parseDisplayName(from: uri),
                    isOutgoing: true
                )
                self.activeCalls[callID] = callInfo

                // Make this the active/displayed call
                self.activeCallID = callID
                self.remotePartyURI = uri
                self.remotePartyName = callInfo.remoteName
                self.callState = .outgoing
                self.isMuted = false
                self.isOnHold = false
                self.currentScreen = .activeCall
            } catch {
                self.errorMessage = "Failed to start call: \(error.localizedDescription)"
                print("AppViewModel: Failed to make call: \(error)")
            }
        }
    }

    /// Answers an incoming call.
    func answerCall() {
        guard let callID = activeCallID else {
            print("AppViewModel: No active call to answer")
            return
        }

        print("AppViewModel: answerCall started for call \(callID)")

        // Check microphone permission first
        requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }

            if !granted {
                self.showMicrophonePermissionError()
                return
            }

            print("AppViewModel: Microphone permission granted, about to hold other calls")

            // Put any active calls on hold first (only holds already-established calls)
            self.holdAllActiveCalls()

            // Stop ringtone BEFORE answering to release audio device
            IncomingCallManager.shared.handleCallEnded()

            print("AppViewModel: Now answering call \(callID)")
            do {
                try TonePhoneCore.shared.answerCall(callID)
                print("AppViewModel: answerCall succeeded for call \(callID)")
            } catch {
                self.errorMessage = "Failed to answer call: \(error.localizedDescription)"
                print("AppViewModel: Failed to answer call: \(error)")
            }
        }
    }

    /// Hangs up the current call.
    func hangupCall() {
        guard let callID = activeCallID else {
            print("AppViewModel: No active call to hang up")
            return
        }

        do {
            try TonePhoneCore.shared.hangupCall(callID)
            // Update the call info in dictionary
            if var callInfo = activeCalls[callID] {
                callInfo.state = .ended(reason: nil)
                activeCalls[callID] = callInfo
            }
            // Immediately show ended state and schedule cleanup
            callState = .ended(reason: nil)
            stopCallDurationTimer()
            scheduleCallCleanup(callID: callID, delay: 1.0)
        } catch {
            errorMessage = "Failed to hang up call: \(error.localizedDescription)"
            print("AppViewModel: Failed to hang up call: \(error)")
        }
    }

    /// Toggles mute state for the current call.
    func toggleMute() {
        guard let callID = activeCallID else {
            print("AppViewModel: No active call to mute")
            return
        }

        let newMuteState = !isMuted
        do {
            try TonePhoneCore.shared.muteCall(callID, mute: newMuteState)
            isMuted = newMuteState
            // Update dictionary
            if var callInfo = activeCalls[callID] {
                callInfo.isMuted = newMuteState
                activeCalls[callID] = callInfo
            }
        } catch {
            errorMessage = "Failed to \(newMuteState ? "mute" : "unmute"): \(error.localizedDescription)"
            print("AppViewModel: Failed to toggle mute: \(error)")
        }
    }

    /// Toggles hold state for the current call.
    func toggleHold() {
        guard let callID = activeCallID else {
            print("AppViewModel: No active call to hold")
            return
        }

        print("AppViewModel: toggleHold called for call \(callID), current isOnHold: \(isOnHold)")
        let newHoldState = !isOnHold
        do {
            try TonePhoneCore.shared.holdCall(callID, hold: newHoldState)
            isOnHold = newHoldState
            callState = newHoldState ? .held : .established
            // Update dictionary
            if var callInfo = activeCalls[callID] {
                callInfo.isOnHold = newHoldState
                callInfo.state = newHoldState ? .held : .established
                activeCalls[callID] = callInfo
            }
        } catch {
            errorMessage = "Failed to \(newHoldState ? "hold" : "resume"): \(error.localizedDescription)"
            print("AppViewModel: Failed to toggle hold: \(error)")
        }
    }

    /// Sends DTMF digits during the current call.
    /// - Parameter digit: The DTMF digit to send.
    func sendDTMF(_ digit: String) {
        guard let callID = activeCallID else {
            print("AppViewModel: No active call for DTMF")
            return
        }

        do {
            try TonePhoneCore.shared.sendDTMF(callID, digits: digit)
        } catch {
            print("AppViewModel: Failed to send DTMF: \(error)")
        }
    }

    /// Sets the target call for actions without navigating.
    /// - Parameter callID: The call ID to target.
    func setTargetCall(_ callID: CallID) {
        guard let callInfo = activeCalls[callID] else {
            print("AppViewModel: Call \(callID) not found")
            return
        }

        activeCallID = callID
        remotePartyURI = callInfo.remoteURI
        remotePartyName = callInfo.remoteName
        callState = callInfo.state
        isMuted = callInfo.isMuted
        isOnHold = callInfo.isOnHold
    }

    /// Selects a call from the list and navigates to the active call view.
    /// - Parameter callID: The call ID to select.
    func selectCall(_ callID: CallID) {
        setTargetCall(callID)
        currentScreen = .activeCall
    }

    // MARK: - Navigation

    /// Goes back to the calls list from the active call view.
    func goBackToCallsList() {
        currentScreen = .activeAccount
    }

    /// Shows the active call detail view.
    func showActiveCall() {
        guard activeCallID != nil else { return }
        currentScreen = .activeCall
    }

    // MARK: - Audio Device Management

    /// UserDefaults keys for audio device preferences.
    private enum AudioDeviceKeys {
        static let inputDeviceName = "selectedInputDeviceName"
        static let outputDeviceName = "selectedOutputDeviceName"
    }

    /// Refreshes the list of available audio devices and validates selections.
    func refreshAudioDevices() {
        inputDevices = TonePhoneCore.shared.getInputDevices()
        outputDevices = TonePhoneCore.shared.getOutputDevices()

        // Validate selected input device still exists
        if let selected = selectedInputDevice, !selected.id.isEmpty {
            if let existing = inputDevices.first(where: { $0.id == selected.id }) {
                selectedInputDevice = existing
            } else {
                // Device no longer exists - fall back to system default
                print("AppViewModel: Input device '\(selected.name)' no longer available, using system default")
                selectedInputDevice = nil
                clearSavedInputDevice()
            }
        }

        // Validate selected output device still exists
        if let selected = selectedOutputDevice, !selected.id.isEmpty {
            if let existing = outputDevices.first(where: { $0.id == selected.id }) {
                selectedOutputDevice = existing
            } else {
                // Device no longer exists - fall back to system default
                print("AppViewModel: Output device '\(selected.name)' no longer available, using system default")
                selectedOutputDevice = nil
                clearSavedOutputDevice()
            }
        }
    }

    /// Loads audio device preferences from UserDefaults and applies them.
    private func loadAudioDevicePreferences() {
        let defaults = UserDefaults.standard

        // First refresh device list
        inputDevices = TonePhoneCore.shared.getInputDevices()
        outputDevices = TonePhoneCore.shared.getOutputDevices()

        // Load and match saved input device
        if let savedInputName = defaults.string(forKey: AudioDeviceKeys.inputDeviceName),
           !savedInputName.isEmpty {
            if let matchingDevice = inputDevices.first(where: { $0.name == savedInputName }) {
                // Apply the saved device
                do {
                    try TonePhoneCore.shared.setInputDevice(matchingDevice)
                    selectedInputDevice = matchingDevice
                    print("AppViewModel: Restored input device: \(matchingDevice.name)")
                } catch {
                    // Failed to apply - keep selection as nil (system default)
                    print("AppViewModel: Failed to restore input device: \(error)")
                    clearSavedInputDevice()
                }
            } else {
                // Saved device no longer exists - clear preference and use default
                print("AppViewModel: Saved input device '\(savedInputName)' not found, using system default")
                clearSavedInputDevice()
            }
        }

        // Load and match saved output device
        if let savedOutputName = defaults.string(forKey: AudioDeviceKeys.outputDeviceName),
           !savedOutputName.isEmpty {
            if let matchingDevice = outputDevices.first(where: { $0.name == savedOutputName }) {
                // Apply the saved device
                do {
                    try TonePhoneCore.shared.setOutputDevice(matchingDevice)
                    selectedOutputDevice = matchingDevice
                    print("AppViewModel: Restored output device: \(matchingDevice.name)")
                } catch {
                    // Failed to apply - keep selection as nil (system default)
                    print("AppViewModel: Failed to restore output device: \(error)")
                    clearSavedOutputDevice()
                }
            } else {
                // Saved device no longer exists - clear preference and use default
                print("AppViewModel: Saved output device '\(savedOutputName)' not found, using system default")
                clearSavedOutputDevice()
            }
        }
    }

    /// Saves audio device preferences to UserDefaults.
    private func saveAudioDevicePreferences() {
        let defaults = UserDefaults.standard

        if let device = selectedInputDevice, !device.id.isEmpty {
            defaults.set(device.name, forKey: AudioDeviceKeys.inputDeviceName)
        } else {
            defaults.removeObject(forKey: AudioDeviceKeys.inputDeviceName)
        }

        if let device = selectedOutputDevice, !device.id.isEmpty {
            defaults.set(device.name, forKey: AudioDeviceKeys.outputDeviceName)
        } else {
            defaults.removeObject(forKey: AudioDeviceKeys.outputDeviceName)
        }
    }

    /// Clears saved input device preference.
    private func clearSavedInputDevice() {
        UserDefaults.standard.removeObject(forKey: AudioDeviceKeys.inputDeviceName)
    }

    /// Clears saved output device preference.
    private func clearSavedOutputDevice() {
        UserDefaults.standard.removeObject(forKey: AudioDeviceKeys.outputDeviceName)
    }

    /// Selects an input device (microphone).
    /// - Parameter device: The device to select, or nil for system default.
    func selectInputDevice(_ device: AudioDevice?) {
        let previousDevice = selectedInputDevice
        selectedInputDevice = device

        do {
            try TonePhoneCore.shared.setInputDevice(device)
            saveAudioDevicePreferences()
            print("AppViewModel: Input device set to \(device?.name ?? "System Default")")
        } catch {
            // Roll back on failure
            selectedInputDevice = previousDevice
            errorMessage = "Failed to set input device: \(error.localizedDescription)"
            print("AppViewModel: Failed to set input device: \(error)")
        }
    }

    /// Selects an output device (speaker).
    /// - Parameter device: The device to select, or nil for system default.
    func selectOutputDevice(_ device: AudioDevice?) {
        let previousDevice = selectedOutputDevice
        selectedOutputDevice = device

        do {
            try TonePhoneCore.shared.setOutputDevice(device)
            saveAudioDevicePreferences()
            print("AppViewModel: Output device set to \(device?.name ?? "System Default")")
        } catch {
            // Roll back on failure
            selectedOutputDevice = previousDevice
            errorMessage = "Failed to set output device: \(error.localizedDescription)"
            print("AppViewModel: Failed to set output device: \(error)")
        }
    }

    /// Returns the name of the current system default input device.
    func getDefaultInputDeviceName() -> String? {
        inputDevices.first(where: { $0.isDefault })?.name
    }

    /// Returns the name of the current system default output device.
    func getDefaultOutputDeviceName() -> String? {
        outputDevices.first(where: { $0.isDefault })?.name
    }

    /// Handles audio device changes (hot-plug events).
    private func handleAudioDeviceChanged() {
        refreshAudioDevices()
    }
}
