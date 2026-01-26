//
//  IncomingCallManager.swift
//  TonePhone
//
//  Manages incoming call alerts, notifications, and ringtone.
//

import AppKit
import AVFoundation
import UserNotifications

/// Manages incoming call alerts including system notifications,
/// ringtone playback, and window focus.
@MainActor
final class IncomingCallManager: NSObject, ObservableObject {
    /// Shared instance for app-wide use.
    static let shared = IncomingCallManager()

    /// Whether a ringtone is currently playing.
    @Published private(set) var isRinging = false

    /// Audio player for ringtone.
    private var audioPlayer: AVAudioPlayer?

    /// Current notification identifier for cleanup.
    private var currentNotificationID: String?

    /// Callback for answering call from notification.
    var onAnswer: (() -> Void)?

    /// Callback for declining call from notification.
    var onDecline: (() -> Void)?

    private override init() {
        super.init()
        setupNotifications()
    }

    // MARK: - Notification Setup

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Define notification actions
        let answerAction = UNNotificationAction(
            identifier: "ANSWER",
            title: "Answer",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "DECLINE",
            title: "Decline",
            options: [.destructive]
        )

        // Create category with actions
        let callCategory = UNNotificationCategory(
            identifier: "INCOMING_CALL",
            actions: [answerAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([callCategory])
    }

    /// Requests notification permission from the user.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("IncomingCallManager: Notification permission error: \(error)")
            } else {
                print("IncomingCallManager: Notification permission granted: \(granted)")
            }
        }
    }

    // MARK: - Incoming Call Handling

    /// Called when an incoming call is received.
    /// - Parameters:
    ///   - callerName: Display name of the caller
    ///   - callerURI: SIP URI of the caller
    func handleIncomingCall(callerName: String?, callerURI: String?) {
        let displayName = callerName ?? callerURI ?? "Unknown Caller"

        // Start ringtone
        startRingtone()

        // Bring app to front
        bringAppToFront()

        // Post notification if app is not active
        if !NSApp.isActive {
            postIncomingCallNotification(caller: displayName)
        }
    }

    /// Called when an incoming call ends (answered, declined, or cancelled).
    func handleCallEnded() {
        stopRingtone()
        removeNotification()
    }

    // MARK: - Ringtone

    private func startRingtone() {
        guard !isRinging else { return }

        // Try to load system ringtone or bundled sound
        if let soundURL = findRingtoneURL() {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.numberOfLoops = -1 // Loop indefinitely
                audioPlayer?.volume = 0.7
                audioPlayer?.play()
                isRinging = true
            } catch {
                print("IncomingCallManager: Failed to play ringtone: \(error)")
                // Fallback to system sound
                playSystemSound()
            }
        } else {
            playSystemSound()
        }
    }

    private func stopRingtone() {
        audioPlayer?.stop()
        audioPlayer = nil
        isRinging = false
    }

    private func findRingtoneURL() -> URL? {
        // First check bundle for custom ringtone
        if let bundleURL = Bundle.main.url(forResource: "ringtone", withExtension: "aiff") {
            return bundleURL
        }
        if let bundleURL = Bundle.main.url(forResource: "ringtone", withExtension: "mp3") {
            return bundleURL
        }

        // Fall back to system ringtone
        let systemRingtones = [
            "/System/Library/Sounds/Ping.aiff",
            "/System/Library/Sounds/Glass.aiff",
            "/System/Library/Sounds/Sosumi.aiff"
        ]

        for path in systemRingtones {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                return url
            }
        }

        return nil
    }

    private func playSystemSound() {
        // Use NSSound for system alert
        NSSound.beep()
        isRinging = true

        // Schedule repeated beeps
        scheduleRepeatedBeeps()
    }

    private var beepTimer: Timer?

    private func scheduleRepeatedBeeps() {
        beepTimer?.invalidate()
        beepTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard self?.isRinging == true else {
                self?.beepTimer?.invalidate()
                self?.beepTimer = nil
                return
            }
            NSSound.beep()
        }
    }

    // MARK: - System Notification

    private func postIncomingCallNotification(caller: String) {
        let content = UNMutableNotificationContent()
        content.title = "Incoming Call"
        content.body = caller
        content.sound = .default
        content.categoryIdentifier = "INCOMING_CALL"
        content.interruptionLevel = .timeSensitive

        let notificationID = UUID().uuidString
        currentNotificationID = notificationID

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("IncomingCallManager: Failed to post notification: \(error)")
            }
        }
    }

    private func removeNotification() {
        if let notificationID = currentNotificationID {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [notificationID]
            )
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [notificationID]
            )
            currentNotificationID = nil
        }
    }

    // MARK: - Window Management

    private func bringAppToFront() {
        NSApp.activate(ignoringOtherApps: true)

        // Also bring the main window to front
        if let window = NSApp.mainWindow ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension IncomingCallManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            switch response.actionIdentifier {
            case "ANSWER":
                self.onAnswer?()
            case "DECLINE", UNNotificationDismissActionIdentifier:
                self.onDecline?()
            default:
                // Default tap - bring app to front
                self.bringAppToFront()
            }
        }

        completionHandler()
    }
}
