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

/// Main view model for tracking application state.
///
/// Subscribes to `TonePhoneCore.events` and maintains a map of account states.
/// Publishes an aggregated `registrationStatus` for the UI to display.
/// Also manages account configuration and persistence.
@MainActor
final class AppViewModel: ObservableObject {
    /// Current registration status for display.
    @Published private(set) var registrationStatus: RegistrationStatus = .notConfigured

    /// Currently configured accounts.
    @Published private(set) var accounts: [SIPAccount] = []

    /// The currently selected account for editing.
    @Published var selectedAccount: SIPAccount?

    /// Whether the account configuration sheet is showing.
    @Published var isAccountSheetPresented = false

    /// Error message to display to user.
    @Published var errorMessage: String?

    /// Whether a connection attempt is in progress.
    @Published private(set) var isConnecting = false

    /// Tracked account states by ID.
    private var accountStates: [AccountID: AccountState] = [:]

    /// Mapping from SIPAccount UUID to bridge AccountID.
    private var accountIDMapping: [UUID: AccountID] = [:]

    /// Combine cancellables for event subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Creates the view model and subscribes to TonePhoneCore events.
    init() {
        subscribeToEvents()
        loadAccounts()
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
                print("Failed to remove account from core: \(error)")
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
            } catch {
                print("Failed to remove existing account: \(error)")
            }
            accountStates.removeValue(forKey: existingBridgeID)
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

    /// Registers all stored accounts with TonePhoneCore.
    /// Called when the app starts or core is restarted.
    func registerStoredAccounts() {
        for account in accounts {
            if let password = AccountStore.shared.getPassword(for: account.id) {
                registerAccountWithCore(account, password: password)
            }
        }
    }

    // MARK: - Connect Button

    /// Title for the connect button based on current state.
    var connectButtonTitle: String {
        switch registrationStatus {
        case .notConfigured:
            return "Connect"
        case .registering:
            return "Connecting..."
        case .registered:
            return "Disconnect"
        case .failed:
            return "Retry"
        }
    }

    /// Whether the connect button should be enabled.
    var canConnect: Bool {
        switch registrationStatus {
        case .registering:
            return false
        default:
            return true
        }
    }

    /// Handles connect button tap.
    /// - Parameter account: The account to connect/disconnect.
    func connectAccount(_ account: SIPAccount) {
        switch registrationStatus {
        case .registered:
            // Disconnect
            disconnectAccount(account)
        case .notConfigured, .failed:
            // Connect
            if let password = AccountStore.shared.getPassword(for: account.id) {
                registerAccountWithCore(account, password: password)
            }
        case .registering:
            // Already connecting, do nothing
            break
        }
    }

    /// Disconnects an account.
    /// - Parameter account: The account to disconnect.
    private func disconnectAccount(_ account: SIPAccount) {
        guard let bridgeID = accountIDMapping[account.id] else { return }

        do {
            try TonePhoneCore.shared.unregisterAccount(bridgeID)
            accountStates[bridgeID] = .unregistered
            updateRegistrationStatus()
        } catch {
            errorMessage = "Failed to disconnect: \(error.localizedDescription)"
        }
    }
}
