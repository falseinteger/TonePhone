//
//  AppViewModel.swift
//  TonePhone
//
//  View model for the main application state.
//  Subscribes to TonePhoneCore events and tracks account registration status.
//

import SwiftUI
import Combine

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
        autoConnectIfNeeded()
        showAddAccountIfEmpty()
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

        case .coreStateChanged, .callStateChanged, .mediaChanged:
            // Handled elsewhere or not needed for registration status
            break
        }
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

        // Add new account to core
        do {
            let bridgeID = try TonePhoneCore.shared.addAccount(
                sipURI: account.sipURI,
                password: password,
                displayName: account.displayName.isEmpty ? nil : account.displayName,
                transport: account.transport.rawValue,
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
}
