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
@MainActor
final class AppViewModel: ObservableObject {
    /// Current registration status for display.
    @Published private(set) var registrationStatus: RegistrationStatus = .notConfigured

    /// Tracked account states by ID.
    private var accountStates: [AccountID: AccountState] = [:]

    /// Combine cancellables for event subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Creates the view model and subscribes to TonePhoneCore events.
    init() {
        subscribeToEvents()
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
}
