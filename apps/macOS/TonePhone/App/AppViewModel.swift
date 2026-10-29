//
//  AppViewModel.swift
//  TonePhone
//
//  View model for the main application state.
//  Subscribes to TonePhoneCore events and tracks account registration and calls.
//

import SwiftUI
import Combine
import AVFoundation

/// Registration status of the account the window is working with.
enum RegistrationStatus: Equatable {
    /// No SIP accounts have been configured.
    case notConfigured
    /// Accounts exist but none is connected.
    case offline
    /// The account is registering.
    case registering
    /// The account is registered.
    case registered
    /// Registration failed.
    case failed(reason: String?)

    /// Human-readable text for display in the UI.
    var displayText: String {
        switch self {
        case .notConfigured:
            return "No Account"
        case .offline:
            return "Not Connected"
        case .registering:
            return "Connecting…"
        case .registered:
            return "Connected"
        case .failed(let reason):
            return reason ?? "Connection Failed"
        }
    }

    /// Color for the status indicator. Always paired with `displayText` or `symbolName`.
    var indicatorColor: Color {
        switch self {
        case .notConfigured, .offline:
            return .secondary
        case .registering:
            return .orange
        case .registered:
            return .green
        case .failed:
            return .red
        }
    }

    /// SF Symbol that conveys the status without relying on color.
    var symbolName: String {
        switch self {
        case .notConfigured, .offline:
            return "circle.dashed"
        case .registering:
            return "arrow.triangle.2.circlepath"
        case .registered:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
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
/// Subscribes to `TonePhoneCore.events`, owns the account connection flow
/// and the list of calls, and records call history.
@MainActor
final class AppViewModel: ObservableObject {
    /// Shared singleton instance for cross-window access (e.g., Settings).
    static let shared = AppViewModel()
    /// Current screen being displayed.
    @Published private(set) var currentScreen: AppScreen = .accountList

    /// Registration status of the connecting or active account.
    @Published private(set) var registrationStatus: RegistrationStatus = .notConfigured

    /// Currently configured accounts.
    @Published private(set) var accounts: [SIPAccount] = []

    /// The currently selected account for editing.
    @Published var selectedAccount: SIPAccount?

    /// Whether the account configuration sheet is showing.
    @Published var isAccountSheetPresented = false

    /// The account currently being connected.
    @Published private(set) var connectingAccount: SIPAccount?

    /// The active (connected) account.
    @Published private(set) var activeAccount: SIPAccount?

    /// Error to present to the user.
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
        /// The account that owns this call (for history recording).
        var ownerAccountID: UUID?
        /// Whether this call has already been recorded in history.
        var historyRecorded: Bool = false
        /// The user declined this incoming call (not counted as missed).
        var declinedByUser: Bool = false
        /// The audio is encrypted (SRTP).
        var isEncrypted: Bool = false

        /// Title and subtitle for the remote party, formatted per settings.
        var labels: (title: String, subtitle: String?) {
            PhoneNumberService.partyLabels(name: remoteName, uri: remoteURI)
        }

        var isIncomingRinging: Bool {
            if case .incoming = state { return true }
            return false
        }
    }

    /// All active calls tracked by ID.
    @Published private(set) var activeCalls: [CallID: CallInfo] = [:]

    /// Voicemail status reported by the server for the active account.
    @Published private(set) var voicemailStatus: VoicemailStatus?

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

    /// Remote party display name sent by the other side, if any.
    @Published private(set) var remotePartyName: String?

    /// Whether the current call is muted.
    @Published private(set) var isMuted = false

    /// Whether the current call is on hold.
    @Published private(set) var isOnHold = false

    /// Call duration in seconds.
    @Published private(set) var callDuration: TimeInterval = 0

    /// Formatted call duration string (M:SS or H:MM:SS).
    var callDurationFormatted: String {
        Self.formatDuration(callDuration)
    }

    /// Title and subtitle for the displayed call's remote party.
    var remotePartyLabels: (title: String, subtitle: String?) {
        PhoneNumberService.partyLabels(name: remotePartyName, uri: remotePartyURI)
    }

    /// Formats a duration as M:SS or H:MM:SS.
    static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Timer for updating call duration.
    private var callDurationTimer: Timer?

    /// Call start time for duration calculation.
    private var callStartTime: Date?

    /// Pending removal of each ended call, so ending one call never
    /// cancels the removal of another.
    private var pendingCleanups: [CallID: DispatchWorkItem] = [:]

    /// An account whose settings changed during a call; it is set up again
    /// once the calls end, because replacing it in the engine drops them.
    private var pendingReregistrationID: UUID?

    /// Tracked account states by bridge ID.
    private var accountStates: [AccountID: AccountState] = [:]

    /// Mapping from SIPAccount UUID to bridge AccountID.
    private var accountIDMapping: [UUID: AccountID] = [:]

    /// Combine cancellables for event subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Creates the view model and subscribes to TonePhoneCore events.
    private init() {
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

        callManager.onAnswer = { [weak self] callID in
            self?.answerCall(callID)
        }

        callManager.onDecline = { [weak self] callID in
            self?.declineCall(callID)
        }

        callManager.onShowCall = { [weak self] callID in
            self?.selectCall(callID)
        }
    }

    /// Shows the add account sheet if no accounts exist.
    private func showAddAccountIfEmpty() {
        if accounts.isEmpty {
            // Present after the window is on screen so the sheet attaches to it
            DispatchQueue.main.async { [weak self] in
                self?.showAddAccountSheet()
            }
        }
    }

    /// Starts the TonePhoneCore SIP engine.
    private func startCore() {
        do {
            try TonePhoneCore.shared.start(options: SettingsStore.shared.coreOptions)
            SettingsStore.shared.applyCoreSettings()
        } catch {
            errorMessage = "TonePhone couldn’t start the calling engine (\(error.localizedDescription)). Quit and reopen TonePhone; if the problem continues, export the logs from Settings › Advanced."
        }
    }

    /// Subscribes to TonePhoneCore events and system notifications.
    private func subscribeToEvents() {
        TonePhoneCore.shared.events
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .accountSettingsChanged)
            .sink { [weak self] notification in
                guard let self, let accountID = notification.object as? UUID else { return }
                self.reregisterAccount(id: accountID)
            }
            .store(in: &cancellables)

        // Network addresses change across sleep; refresh the registration on wake
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.refreshRegistrationAfterWake()
            }
            .store(in: &cancellables)
    }

    /// Re-registers an account after its settings changed.
    private func reregisterAccount(id: UUID) {
        loadAccounts()

        // Only the account in use is registered with the engine
        guard let account = accounts.first(where: { $0.id == id }),
              account.id == activeAccount?.id || account.id == connectingAccount?.id,
              let password = AccountStore.shared.getPassword(for: id) else { return }

        if activeAccount?.id == id { activeAccount = account }
        if connectingAccount?.id == id { connectingAccount = account }
        guard activeCalls.isEmpty else {
            pendingReregistrationID = id
            return
        }
        registerAccountWithCore(account, password: password)
    }

    /// Sends a fresh REGISTER for the active account after the Mac wakes.
    private func refreshRegistrationAfterWake() {
        guard let account = activeAccount ?? connectingAccount,
              let bridgeID = accountIDMapping[account.id] else { return }
        try? TonePhoneCore.shared.registerAccount(bridgeID)
    }

    /// Handles incoming events from TonePhoneCore.
    /// - Parameter event: The event to process.
    private func handleEvent(_ event: TonePhoneEvent) {
        switch event {
        case .accountStateChanged(let accountID, let state):
            // Ignore late events from accounts that were removed
            guard accountIDMapping.values.contains(accountID) else { return }
            accountStates[accountID] = state
            updateRegistrationStatus()

            // Handle connection completion - only for the account we're connecting
            if let connectingAccount,
               accountIDMapping[connectingAccount.id] == accountID {
                switch state {
                case .registered:
                    completeConnection()
                case .failed:
                    // Auto-login failed: go to account list and show error
                    if currentScreen == .connecting {
                        errorMessage = "Couldn’t connect to \(connectingAccount.title). \(registrationStatus.displayText)"
                        removeAccountFromCore(connectingAccount.id)
                        self.connectingAccount = nil
                        currentScreen = .accountList
                        updateRegistrationStatus()
                    }
                default:
                    break
                }
            }

        case .callStateChanged(let callID, let state, let details):
            handleCallStateChanged(callID: callID, state: state, details: details)

        case .audioDeviceChanged:
            handleAudioDeviceChanged()

        case .mediaChanged(let callID, _, _, let encrypted):
            if encrypted, var info = activeCalls[callID] {
                info.isEncrypted = true
                activeCalls[callID] = info
            }

        case .messageWaiting(let accountID, let status):
            guard let account = activeAccount ?? connectingAccount,
                  accountIDMapping[account.id] == accountID else { return }
            voicemailStatus = status
            updateDockBadge()

        case .coreStateChanged:
            break
        }
    }

    /// Maps a bridge account ID back to the stored account.
    private func account(forBridgeID bridgeID: AccountID) -> SIPAccount? {
        guard let uuid = accountIDMapping.first(where: { $0.value == bridgeID })?.key else { return nil }
        return accounts.first { $0.id == uuid }
    }

    /// Handles call state changes from TonePhoneCore.
    private func handleCallStateChanged(callID: CallID, state: CallState, details: CallEventDetails) {
        var callInfo = activeCalls[callID] ?? CallInfo(id: callID, state: .idle)
        if let name = details.remoteName {
            callInfo.remoteName = name
        }
        if callInfo.ownerAccountID == nil {
            callInfo.ownerAccountID = account(forBridgeID: details.accountID)?.id ?? activeAccount?.id
        }

        switch state {
        case .idle:
            if callInfo.remoteURI != nil {
                recordCallHistory(callInfo)
            }
            activeCalls.removeValue(forKey: callID)
            IncomingCallManager.shared.handleCallEnded(callID)
            if activeCallID == callID {
                switchToNextCallOrClear()
            }

        case .outgoing:
            callInfo.state = .outgoing
            callInfo.isOutgoing = true
            activeCalls[callID] = callInfo
            if activeCallID == nil || activeCallID == callID {
                showCall(callInfo)
            }

        case .incoming(let remoteURI):
            callInfo.state = .incoming(remoteURI: remoteURI)
            callInfo.remoteURI = remoteURI
            activeCalls[callID] = callInfo

            // Show the incoming call unless the user is already talking;
            // a second call rings in the panel and the calls list (call waiting)
            let isBusy = activeCalls.values.contains { $0.id != callID && $0.state == .established }
            if !isBusy {
                showCall(callInfo)
            }

            let labels = callInfo.labels
            IncomingCallManager.shared.handleIncomingCall(
                callID: callID,
                title: labels.title,
                subtitle: labels.subtitle,
                accountName: callInfo.ownerAccountID.flatMap { id in accounts.first { $0.id == id }?.title }
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
            if callInfo.startTime == nil {
                callInfo.startTime = Date()
            }
            activeCalls[callID] = callInfo
            IncomingCallManager.shared.handleCallAnswered(callID)
            if activeCallID == callID {
                callState = .established
                isOnHold = false
                startCallDurationTimer(from: callInfo.startTime)
            }

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
            recordCallHistory(callInfo)
            callInfo.historyRecorded = true
            activeCalls[callID] = callInfo
            IncomingCallManager.shared.handleCallEnded(callID)
            if activeCallID == callID {
                callState = .ended(reason: reason)
                stopCallDurationTimer()
            }
            scheduleCallCleanup(callID: callID, delay: 1.5)
        }
    }

    /// Makes a call the displayed call and shows the call window.
    private func showCall(_ callInfo: CallInfo) {
        activeCallID = callInfo.id
        remotePartyURI = callInfo.remoteURI
        remotePartyName = callInfo.remoteName
        callState = callInfo.state
        isMuted = callInfo.isMuted
        isOnHold = callInfo.isOnHold
        if callInfo.startTime != nil {
            startCallDurationTimer(from: callInfo.startTime)
        } else {
            stopCallDurationTimer()
            callDuration = 0
        }
        CallWindow.show()
    }

    /// Switches to the next available call or clears call state if none.
    private func switchToNextCallOrClear() {
        // Prefer a ringing call, then a connected one, then a held one
        let remaining = activeCalls.values.filter {
            if case .ended = $0.state { return false }
            return true
        }
        let nextCall = remaining.first { $0.isIncomingRinging }
            ?? remaining.first { $0.state == .established }
            ?? remaining.first { $0.state == .held }
            ?? remaining.first

        if let nextCall {
            showCall(nextCall)
        } else {
            clearCallState()
            CallWindow.close()
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
    }

    /// Schedules removal of an ended call so its final state stays visible briefly.
    private func scheduleCallCleanup(callID: CallID, delay: TimeInterval = 1.0) {
        pendingCleanups[callID]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCleanups[callID] = nil
            self.activeCalls.removeValue(forKey: callID)
            if self.activeCallID == callID {
                self.switchToNextCallOrClear()
            }
            if self.activeCalls.isEmpty, let id = self.pendingReregistrationID {
                self.pendingReregistrationID = nil
                self.reregisterAccount(id: id)
            }
        }

        pendingCleanups[callID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancels every pending removal; used when all calls are dropped at once.
    private func cancelPendingCleanups() {
        pendingCleanups.values.forEach { $0.cancel() }
        pendingCleanups.removeAll()
    }

    /// Records a completed call in the call history.
    private func recordCallHistory(_ callInfo: CallInfo) {
        guard !callInfo.historyRecorded else { return }
        guard let accountID = callInfo.ownerAccountID ?? activeAccount?.id else { return }

        let direction: CallDirection
        if callInfo.isOutgoing {
            direction = .outbound
        } else if callInfo.startTime != nil {
            direction = .inbound
        } else {
            direction = .missed
        }

        let duration = callInfo.startTime.map { Date().timeIntervalSince($0) } ?? 0
        let remoteAddress = PhoneNumberService.address(ofURI: callInfo.remoteURI ?? "")

        let record = CallRecord(
            accountID: accountID,
            remoteURI: remoteAddress.isEmpty ? "Unknown" : remoteAddress,
            remoteName: callInfo.remoteName,
            direction: direction,
            duration: duration
        )

        CallHistoryStore.shared.addRecord(record)
        NotificationCenter.default.post(name: .callHistoryDidChange, object: nil)

        if direction == .missed && !callInfo.declinedByUser {
            IncomingCallManager.shared.postMissedCallNotification(title: callInfo.labels.title)
        }
    }

    /// Starts the call duration timer.
    private func startCallDurationTimer(from start: Date?) {
        callStartTime = start ?? Date()
        callDuration = Date().timeIntervalSince(callStartTime ?? Date())
        callDurationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let startTime = self.callStartTime else { return }
                self.callDuration = Date().timeIntervalSince(startTime)
            }
        }
        // .common keeps the timer running while menus or popovers track events
        RunLoop.main.add(timer, forMode: .common)
        callDurationTimer = timer
    }

    /// Stops the call duration timer.
    private func stopCallDurationTimer() {
        callDurationTimer?.invalidate()
        callDurationTimer = nil
    }

    /// Recalculates the registration status of the connecting or active account.
    private func updateRegistrationStatus() {
        guard !accounts.isEmpty else {
            registrationStatus = .notConfigured
            return
        }

        guard let account = connectingAccount ?? activeAccount,
              let bridgeID = accountIDMapping[account.id],
              let state = accountStates[bridgeID] else {
            registrationStatus = .offline
            return
        }

        switch state {
        case .registered:
            registrationStatus = .registered
        case .registering:
            registrationStatus = .registering
        case .unregistered:
            registrationStatus = .offline
        case .failed(let reason):
            registrationStatus = .failed(reason: Self.friendlyRegistrationError(reason, account: account))
        }
    }

    /// Turns a SIP or socket error into a sentence that says what to check.
    static func friendlyRegistrationError(_ reason: String?, account: SIPAccount) -> String {
        let raw = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()
        let code = Int(raw.prefix(3))

        let message: String
        switch code {
        case 401, 407:
            message = "The username or password is incorrect."
        case 403:
            message = "The server refused this account. Check the username, password and authentication username."
        case 404:
            message = "The server doesn’t know this account. Check the username and domain."
        case 408, 480, 503, 504:
            message = "The server didn’t respond. Check the server address, port and transport."
        case 423:
            message = "The server requires a different registration interval."
        default:
            if lowered.contains("timed out") || lowered.contains("timeout") {
                message = "The server didn’t respond. Check the server address, port and transport (\(account.transport.displayName))."
            } else if lowered.contains("refused") {
                message = "The server refused the connection. Check the port and transport (\(account.transport.displayName))."
            } else if lowered.contains("certificate") || lowered.contains("tls") || lowered.contains("ssl") ||
                        (account.transport == .tls && lowered.contains("protocol error")) {
                // A failed TLS handshake (e.g. an unknown certificate authority)
                // only reaches us as a protocol error
                message = "A secure connection couldn’t be established. If your provider uses its own certificate authority, import it in Settings › Advanced."
            } else if lowered.contains("resolve") || lowered.contains("dns") || lowered.contains("no such") ||
                        lowered.contains("not known") || lowered.contains("destination address required") {
                message = "The server address couldn’t be found. Check the domain name."
            } else if lowered.contains("unreachable") || lowered.contains("no route") || lowered.contains("network is down") {
                message = "The network is unavailable. Check your internet connection."
            } else {
                message = "Registration failed."
            }
        }

        return raw.isEmpty ? message : "\(message) (\(raw))"
    }

    // MARK: - Account Management

    /// Loads accounts from persistent storage.
    private func loadAccounts() {
        accounts = AccountStore.shared.loadAccounts()
        updateRegistrationStatus()
    }

    /// Auto-connects to an account if autoLogin is enabled.
    private func autoConnectIfNeeded() {
        guard SettingsStore.shared.registerOnStartup,
              let autoLoginAccount = accounts.first(where: { $0.autoLogin }) else {
            updateRegistrationStatus()
            return
        }

        connectingAccount = autoLoginAccount
        currentScreen = .connecting

        if let password = AccountStore.shared.getPassword(for: autoLoginAccount.id) {
            registerAccountWithCore(autoLoginAccount, password: password)
        } else {
            errorMessage = "The password for \(autoLoginAccount.title) is missing. Edit the account to enter it again."
            connectingAccount = nil
            currentScreen = .accountList
            updateRegistrationStatus()
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

    /// Saves an account. A new account connects right away; an edited
    /// account reconnects only if it is in use.
    func saveAccount(_ account: SIPAccount, password: String) {
        let isNew = !accounts.contains { $0.id == account.id }

        AccountStore.shared.saveAccount(account)
        AccountStore.shared.savePassword(password, for: account.id)
        loadAccounts()

        if isNew {
            startConnection(for: account)
        } else if account.id == activeAccount?.id || account.id == connectingAccount?.id {
            reregisterAccount(id: account.id)
        }
    }

    /// Deletes an account.
    /// - Parameter id: The UUID of the account to delete.
    func deleteAccount(id: UUID) {
        if activeAccount?.id == id {
            disconnect()
        }
        if connectingAccount?.id == id {
            cancelConnection()
        }
        removeAccountFromCore(id)

        AccountStore.shared.deleteAccount(id: id)
        loadAccounts()
    }

    /// Removes an account's user agent from the engine (unregisters it).
    private func removeAccountFromCore(_ id: UUID) {
        guard let bridgeID = accountIDMapping.removeValue(forKey: id) else { return }
        accountStates.removeValue(forKey: bridgeID)
        try? TonePhoneCore.shared.removeAccount(bridgeID)
    }

    /// Builds the engine configuration for an account, applying global defaults.
    private func configuration(for account: SIPAccount, password: String) -> AccountConfiguration {
        let settings = SettingsStore.shared
        let stunServer = account.stunServerOverride ?? settings.stunServers.first ?? settings.stunServer
        let natMethod = account.natMethodOverride ?? settings.natMethod
        let dtmfMode = account.dtmfModeOverride ?? settings.dtmfMode

        return AccountConfiguration(
            sipURI: account.sipURI,
            password: password,
            displayName: account.displayName.isEmpty ? nil : account.displayName,
            authUsername: account.authUsername.trimmingCharacters(in: .whitespaces),
            outboundProxy: account.outboundProxyURI,
            transport: account.transport.rawValue,
            stunServer: natMethod == .none || stunServer.isEmpty ? nil : stunServer,
            mediaNAT: natMethod == .none ? nil : natMethod.rawValue,
            mediaEncryption: account.mediaEncryption.engineValue,
            dtmfMode: dtmfMode.engineValue,
            registrationInterval: UInt32(max(60, account.registrationInterval)),
            natPinhole: account.natPinholeOverride ?? settings.natPinhole,
            voicemailNotifications: account.voicemailNotifications,
            registerImmediately: true
        )
    }

    /// Creates the account in the engine (replacing any previous instance) and registers it.
    private func registerAccountWithCore(_ account: SIPAccount, password: String) {
        removeAccountFromCore(account.id)
        // A new registration subscribes again and gets a fresh status
        voicemailStatus = nil
        updateDockBadge()

        do {
            let bridgeID = try TonePhoneCore.shared.addAccount(configuration(for: account, password: password))
            accountIDMapping[account.id] = bridgeID
            // Events arrive asynchronously; start in the registering state
            accountStates[bridgeID] = .registering
            updateRegistrationStatus()
        } catch {
            let message = error as? TonePhoneError == .invalidArgument
                ? "The account settings aren’t valid. Check the server address, port and username."
                : error.localizedDescription
            if connectingAccount?.id == account.id {
                registrationStatus = .failed(reason: message)
                if currentScreen == .connecting {
                    errorMessage = "Couldn’t connect to \(account.title). \(message)"
                    connectingAccount = nil
                    currentScreen = .accountList
                }
            } else {
                errorMessage = message
            }
        }
    }

    // MARK: - Connection Flow

    /// Connects to an account, disconnecting the current one first.
    /// Shows the connection progress sheet.
    func startConnection(for account: SIPAccount) {
        guard let password = AccountStore.shared.getPassword(for: account.id) else {
            errorMessage = "The password for \(account.title) is missing. Edit the account to enter it again."
            return
        }

        // Switching accounts: only one account is registered at a time
        if let previous = connectingAccount, previous.id != account.id {
            removeAccountFromCore(previous.id)
        }
        if let current = activeAccount, current.id != account.id {
            guard activeCalls.isEmpty else {
                errorMessage = "End your current calls before switching accounts."
                return
            }
            removeAccountFromCore(current.id)
            activeAccount = nil
        }

        // Reconnecting the account in use: register it again rather than
        // replacing it, which would drop its calls
        if activeAccount?.id == account.id, let bridgeID = accountIDMapping[account.id] {
            accountStates[bridgeID] = .registering
            updateRegistrationStatus()
            do {
                try TonePhoneCore.shared.registerAccount(bridgeID)
            } catch {
                errorMessage = "\(account.title) couldn’t reconnect: \(error.localizedDescription)"
            }
            return
        }

        connectingAccount = account
        registerAccountWithCore(account, password: password)
    }

    /// Cancels the current connection attempt.
    func cancelConnection() {
        if let account = connectingAccount {
            removeAccountFromCore(account.id)
        }
        connectingAccount = nil
        updateRegistrationStatus()
    }

    /// Cancels auto-connect and goes to account list.
    func cancelAutoConnect() {
        cancelConnection()
        currentScreen = .accountList
    }

    /// Retries the connection for the current account.
    func retryConnection() {
        guard let account = connectingAccount else { return }

        if let password = AccountStore.shared.getPassword(for: account.id) {
            registerAccountWithCore(account, password: password)
        } else {
            errorMessage = "The password for \(account.title) is missing. Edit the account to enter it again."
        }
    }

    /// Opens the account editor for the connecting account.
    func editConnectingAccount() {
        guard let account = connectingAccount else { return }
        cancelConnection()
        showEditAccountSheet(for: account)
    }

    /// Completes the connection and transitions to active account screen.
    func completeConnection() {
        guard let account = connectingAccount else { return }
        activeAccount = account
        connectingAccount = nil
        if let bridgeID = accountIDMapping[account.id] {
            // Outgoing calls use the engine's default account
            try? TonePhoneCore.shared.setDefaultAccount(bridgeID)
        }
        currentScreen = .activeAccount
        updateRegistrationStatus()
    }

    /// Disconnects the active account and returns to the account list.
    func disconnect() {
        for callID in activeCalls.keys {
            try? TonePhoneCore.shared.hangupCall(callID)
        }
        if let account = activeAccount {
            removeAccountFromCore(account.id)
        }

        activeAccount = nil
        voicemailStatus = nil
        updateDockBadge()
        clearCallState()
        cancelPendingCleanups()
        activeCalls.removeAll()
        CallWindow.close()
        currentScreen = .accountList
        updateRegistrationStatus()
    }

    // MARK: - Call Control

    /// Puts all active (non-held, established) calls on hold, except one.
    private func holdAllActiveCalls(except keep: CallID? = nil) {
        for (callID, callInfo) in activeCalls where callID != keep {
            guard case .established = callInfo.state, !callInfo.isOnHold else { continue }
            do {
                try TonePhoneCore.shared.holdCall(callID, hold: true)
                var updatedInfo = callInfo
                updatedInfo.isOnHold = true
                updatedInfo.state = .held
                activeCalls[callID] = updatedInfo
            } catch {
                // The call may have ended in the meantime; nothing to hold
            }
        }
    }

    // MARK: - Microphone Permission

    /// Requests microphone permission and calls completion with result.
    private func requestMicrophonePermission(completion: @escaping @MainActor (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { completion(granted) }
                }
            }
        default:
            completion(false)
        }
    }

    /// Shows an error message about microphone permission.
    private func showMicrophonePermissionError() {
        errorMessage = "TonePhone needs access to the microphone for calls. Turn it on in System Settings › Privacy & Security › Microphone."
    }

    /// Builds a SIP URI for what the user dialed, using the active account.
    ///
    /// Phone numbers are converted to the account's dial format; SIP
    /// addresses, usernames and extensions pass through unchanged.
    func dialURI(for input: String) -> String? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let lowered = cleaned.lowercased()
        if lowered.hasPrefix("sip:") || lowered.hasPrefix("sips:") {
            return cleaned.filter { !$0.isWhitespace }
        }
        if cleaned.contains("@") {
            return "sip:\(cleaned.filter { !$0.isWhitespace })"
        }

        let user: String
        if PhoneNumberService.looksLikeAddress(cleaned) {
            user = cleaned.filter { !$0.isWhitespace }
        } else {
            user = PhoneNumberService.dialString(for: cleaned, format: activeAccount?.dialFormatOverride)
        }
        guard !user.isEmpty else { return nil }

        let escaped = SIPAccount.escapeUserPart(user)
        guard let account = activeAccount else { return "sip:\(escaped)" }
        return "sip:\(escaped)@\(account.hostPort)"
    }

    /// Whether the active account has a voicemail number to call.
    var canCallVoicemail: Bool {
        guard let account = activeAccount else { return false }
        return !account.voicemailNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Calls the active account's voicemail.
    func callVoicemail() {
        guard canCallVoicemail, let account = activeAccount else { return }
        dial(account.voicemailNumber)
    }

    /// Shows the number of new voicemail messages on the Dock icon.
    private func updateDockBadge() {
        guard let status = voicemailStatus, status.hasNewMessages else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        // Some servers only say that messages are waiting
        NSApp.dockTile.badgeLabel = status.newMessages.map(String.init) ?? "•"
    }

    /// Dials a number, username or SIP address.
    func dial(_ input: String) {
        guard let uri = dialURI(for: input) else { return }
        makeCall(to: uri)
    }

    /// Makes an outgoing call to the specified URI.
    /// - Parameter uri: The SIP URI to call.
    func makeCall(to uri: String) {
        requestMicrophonePermission { [weak self] granted in
            guard let self else { return }

            guard granted else {
                self.showMicrophonePermissionError()
                return
            }

            self.holdAllActiveCalls()

            // Calls go out through the engine's default account; make sure
            // it is the one on screen
            if let account = self.activeAccount, let bridgeID = self.accountIDMapping[account.id] {
                try? TonePhoneCore.shared.setDefaultAccount(bridgeID)
            }

            do {
                let callID = try TonePhoneCore.shared.makeCall(to: uri)

                // The OUTGOING event may already have created the entry
                var callInfo = self.activeCalls[callID] ?? CallInfo(id: callID, state: .outgoing)
                callInfo.remoteURI = uri
                callInfo.isOutgoing = true
                callInfo.ownerAccountID = callInfo.ownerAccountID ?? self.activeAccount?.id
                if callInfo.state == .idle { callInfo.state = .outgoing }
                self.activeCalls[callID] = callInfo
                self.showCall(callInfo)
            } catch {
                self.errorMessage = "The call couldn’t be started. Check the number or address and your connection."
            }
        }
    }

    /// Answers the displayed incoming call.
    func answerCall() {
        guard let callID = activeCallID else { return }
        answerCall(callID)
    }

    /// Answers an incoming call, holding any other connected call.
    func answerCall(_ callID: CallID) {
        guard let callInfo = activeCalls[callID], callInfo.isIncomingRinging else { return }

        requestMicrophonePermission { [weak self] granted in
            guard let self else { return }

            guard granted else {
                self.showMicrophonePermissionError()
                return
            }

            self.holdAllActiveCalls(except: callID)

            // Stop the ringtone before answering to release the audio device
            IncomingCallManager.shared.handleCallAnswered(callID)

            do {
                try TonePhoneCore.shared.answerCall(callID)
                if let info = self.activeCalls[callID] {
                    self.showCall(info)
                }
            } catch {
                self.errorMessage = "The call couldn’t be answered. The caller may have hung up."
            }
        }
    }

    /// Ends every other call, then answers this one.
    func endAndAnswerCall(_ callID: CallID) {
        guard activeCalls[callID]?.isIncomingRinging == true else { return }
        for other in activeCalls.values where other.id != callID && !other.isIncomingRinging {
            hangupCall(other.id)
        }
        answerCall(callID)
    }

    /// Declines an incoming call.
    func declineCall(_ callID: CallID) {
        if var callInfo = activeCalls[callID] {
            callInfo.declinedByUser = true
            activeCalls[callID] = callInfo
        }
        hangupCall(callID)
    }

    /// Hangs up the displayed call.
    func hangupCall() {
        guard let callID = activeCallID else { return }
        if activeCalls[callID]?.isIncomingRinging == true {
            declineCall(callID)
        } else {
            hangupCall(callID)
        }
    }

    /// Hangs up a call. The engine reports the end with an ENDED event.
    func hangupCall(_ callID: CallID) {
        IncomingCallManager.shared.handleCallEnded(callID)

        do {
            try TonePhoneCore.shared.hangupCall(callID)
        } catch TonePhoneError.notFound {
            // Already ended on the engine side; clean up locally
            if var callInfo = activeCalls[callID] {
                recordCallHistory(callInfo)
                callInfo.historyRecorded = true
                callInfo.state = .ended(reason: nil)
                activeCalls[callID] = callInfo
            }
            if activeCallID == callID {
                callState = .ended(reason: nil)
                stopCallDurationTimer()
            }
            scheduleCallCleanup(callID: callID, delay: 0.5)
        } catch {
            errorMessage = "The call couldn’t be ended: \(error.localizedDescription)"
        }
    }

    /// Toggles mute state for the current call.
    func toggleMute() {
        guard let callID = activeCallID else { return }

        let newMuteState = !isMuted
        do {
            try TonePhoneCore.shared.muteCall(callID, mute: newMuteState)
            isMuted = newMuteState
            activeCalls[callID]?.isMuted = newMuteState
        } catch {
            errorMessage = "The microphone couldn’t be \(newMuteState ? "muted" : "unmuted")."
        }
    }

    /// Toggles hold state for the current call.
    func toggleHold() {
        guard let callID = activeCallID else { return }

        let newHoldState = !isOnHold
        do {
            if !newHoldState {
                // Resuming one call holds the others
                holdAllActiveCalls(except: callID)
            }
            try TonePhoneCore.shared.holdCall(callID, hold: newHoldState)
            isOnHold = newHoldState
            callState = newHoldState ? .held : .established
            activeCalls[callID]?.isOnHold = newHoldState
            activeCalls[callID]?.state = newHoldState ? .held : .established
        } catch {
            errorMessage = "The call couldn’t be \(newHoldState ? "put on hold" : "resumed")."
        }
    }

    /// Sends DTMF digits during the current call.
    /// - Parameter digit: The DTMF digit to send.
    func sendDTMF(_ digit: String) {
        guard let callID = activeCallID else { return }
        try? TonePhoneCore.shared.sendDTMF(callID, digits: digit)
    }

    /// Sets the target call for actions without navigating.
    /// - Parameter callID: The call ID to target.
    func setTargetCall(_ callID: CallID) {
        guard let callInfo = activeCalls[callID] else { return }

        activeCallID = callID
        remotePartyURI = callInfo.remoteURI
        remotePartyName = callInfo.remoteName
        callState = callInfo.state
        isMuted = callInfo.isMuted
        isOnHold = callInfo.isOnHold
        if callInfo.startTime != nil {
            startCallDurationTimer(from: callInfo.startTime)
        }
    }

    /// Selects a call from the list and navigates to the active call view.
    /// - Parameter callID: The call ID to select.
    func selectCall(_ callID: CallID) {
        guard let callInfo = activeCalls[callID] else { return }
        showCall(callInfo)
    }

    /// Holds the displayed call and resumes another one.
    func switchToCall(_ callID: CallID) {
        guard let callInfo = activeCalls[callID] else { return }
        holdAllActiveCalls(except: callID)
        if callInfo.isOnHold || callInfo.state == .held {
            do {
                try TonePhoneCore.shared.holdCall(callID, hold: false)
                activeCalls[callID]?.isOnHold = false
                activeCalls[callID]?.state = .established
            } catch {
                errorMessage = "The call couldn’t be resumed."
                return
            }
        }
        if let updated = activeCalls[callID] {
            showCall(updated)
        }
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
                } catch {
                    // Failed to apply - keep selection as nil (system default)
                    clearSavedInputDevice()
                }
            } else {
                // Saved device no longer exists - clear preference and use default
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
                } catch {
                    // Failed to apply - keep selection as nil (system default)
                    clearSavedOutputDevice()
                }
            } else {
                // Saved device no longer exists - clear preference and use default
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
        } catch {
            // Roll back on failure
            selectedInputDevice = previousDevice
            errorMessage = "Failed to set input device: \(error.localizedDescription)"
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
        } catch {
            // Roll back on failure
            selectedOutputDevice = previousDevice
            errorMessage = "Failed to set output device: \(error.localizedDescription)"
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
