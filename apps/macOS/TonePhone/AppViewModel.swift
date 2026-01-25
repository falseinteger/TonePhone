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
enum RegistrationStatus: Equatable {
    case notConfigured
    case registering
    case registered
    case failed(reason: String?)

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
@MainActor
final class AppViewModel: ObservableObject {
    /// Current registration status for display.
    @Published private(set) var registrationStatus: RegistrationStatus = .notConfigured

    /// Tracked account states by ID.
    private var accountStates: [AccountID: AccountState] = [:]

    /// Combine cancellables.
    private var cancellables = Set<AnyCancellable>()

    init() {
        subscribeToEvents()
    }

    private func subscribeToEvents() {
        TonePhoneCore.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }

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

    private func updateRegistrationStatus() {
        // If no accounts, show not configured
        guard !accountStates.isEmpty else {
            registrationStatus = .notConfigured
            return
        }

        // Priority: if any account is registered, show registered
        // If any is registering, show registering
        // If all failed, show failed with first error
        // Otherwise show not configured

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
