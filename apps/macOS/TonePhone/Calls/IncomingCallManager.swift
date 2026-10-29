//
//  IncomingCallManager.swift
//  TonePhone
//
//  Rings for incoming calls and alerts the user when TonePhone is in the background.
//

import AppKit
import AVFoundation
import UserNotifications

/// Manages incoming call alerts: ringtone, Dock attention, and notifications.
///
/// When TonePhone is frontmost, the call screen in the main window is the
/// alert. When it is in the background, a notification with Answer and
/// Decline actions is posted and the Dock icon bounces. The app never
/// activates itself, so a call can't steal keyboard focus from the user.
@MainActor
final class IncomingCallManager: NSObject, ObservableObject {
    /// Shared instance for app-wide use.
    static let shared = IncomingCallManager()

    /// Whether a ringtone is currently playing.
    @Published private(set) var isRinging = false

    /// Answer a call from its notification.
    var onAnswer: ((CallID) -> Void)?

    /// Decline a call from its notification.
    var onDecline: ((CallID) -> Void)?

    /// Show a call after the user clicks its notification.
    var onShowCall: ((CallID) -> Void)?

    private enum Identifier {
        static let incomingCategory = "INCOMING_CALL"
        static let answerAction = "ANSWER"
        static let declineAction = "DECLINE"
        static let callIDKey = "callID"

        static func incoming(_ callID: CallID) -> String { "incoming-\(callID.rawValue)" }
    }

    /// Calls that are currently ringing.
    private var ringingCalls: Set<CallID> = []

    /// Audio player for the ringtone.
    private var audioPlayer: AVAudioPlayer?

    /// Dock bounce request, cancelled when ringing stops.
    private var attentionRequest: Int?

    /// Whether notifications have been configured.
    private var notificationsConfigured = false

    private override init() {
        super.init()
        // UNUserNotificationCenter is configured after launch
    }

    // MARK: - Notification Setup

    /// Sets up notification categories and delegate. Must be called after app launch.
    private func setupNotificationsIfNeeded() {
        guard !notificationsConfigured else { return }
        notificationsConfigured = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let answerAction = UNNotificationAction(
            identifier: Identifier.answerAction,
            title: "Answer",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: Identifier.declineAction,
            title: "Decline",
            options: [.destructive]
        )

        let callCategory = UNNotificationCategory(
            identifier: Identifier.incomingCategory,
            actions: [answerAction, declineAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([callCategory])
    }

    /// Requests notification permission from the user. Call after app has launched.
    func requestNotificationPermission() {
        DispatchQueue.main.async { [weak self] in
            self?.setupNotificationsIfNeeded()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: - Call Events

    /// Starts ringing for an incoming call.
    /// - Parameters:
    ///   - callID: The ringing call.
    ///   - title: Caller name or formatted number.
    ///   - subtitle: Formatted number when `title` is a name.
    ///   - accountName: The account receiving the call.
    func handleIncomingCall(callID: CallID, title: String, subtitle: String?, accountName: String?) {
        ringingCalls.insert(callID)
        startRingtone()

        if NSApp.isActive {
            // Frontmost: the main window shows the call; reopen it if it was closed
            MainWindow.show()
            return
        }

        attentionRequest = NSApp.requestUserAttention(.criticalRequest)
        postIncomingCallNotification(callID: callID, title: title, subtitle: subtitle, accountName: accountName)
    }

    /// The call was answered: stop ringing for it.
    func handleCallAnswered(_ callID: CallID) {
        stopAlerting(for: callID)
    }

    /// The call ended (declined, cancelled by the caller, or hung up).
    func handleCallEnded(_ callID: CallID) {
        stopAlerting(for: callID)
    }

    private func stopAlerting(for callID: CallID) {
        ringingCalls.remove(callID)
        removeNotification(identifier: Identifier.incoming(callID))

        guard ringingCalls.isEmpty else { return }
        stopRingtone()
        if let attentionRequest {
            NSApp.cancelUserAttentionRequest(attentionRequest)
            self.attentionRequest = nil
        }
    }

    // MARK: - Ringtone

    private func startRingtone() {
        guard !isRinging else { return }

        guard let soundURL = findRingtoneURL(),
              let player = try? AVAudioPlayer(contentsOf: soundURL) else {
            NSSound.beep()
            return
        }

        player.numberOfLoops = -1
        player.volume = 0.7
        player.play()
        audioPlayer = player
        isRinging = true
    }

    private func stopRingtone() {
        audioPlayer?.stop()
        audioPlayer = nil
        isRinging = false
    }

    private func findRingtoneURL() -> URL? {
        for ext in ["aiff", "caf", "mp3"] {
            if let bundleURL = Bundle.main.url(forResource: "ringtone", withExtension: ext) {
                return bundleURL
            }
        }

        let selectedRingtone = SettingsStore.shared.selectedRingtone
        let candidates = [selectedRingtone, "Ping.aiff", "Glass.aiff", "Sosumi.aiff"]
        return candidates
            .map { URL(fileURLWithPath: "/System/Library/Sounds/\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Notifications

    private func postIncomingCallNotification(callID: CallID, title: String, subtitle: String?, accountName: String?) {
        setupNotificationsIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle ?? ""
        content.body = accountName.map { "Incoming call on \($0)" } ?? "Incoming call"
        content.categoryIdentifier = Identifier.incomingCategory
        content.userInfo = [Identifier.callIDKey: callID.rawValue]
        // The ringtone is already playing; avoid a second sound

        let request = UNNotificationRequest(identifier: Identifier.incoming(callID), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Notifies the user about a call they didn't answer.
    func postMissedCallNotification(title: String) {
        guard !NSApp.isActive else { return }
        setupNotificationsIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "Missed Call"
        content.body = title
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func removeNotification(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension IncomingCallManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // When TonePhone is frontmost the call screen is already showing
        completionHandler([])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawID = response.notification.request.content.userInfo[Identifier.callIDKey] as? UInt32
        let action = response.actionIdentifier

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let rawID else { return }
                let callID = CallID(rawValue: rawID)
                switch action {
                case Identifier.answerAction:
                    MainWindow.show()
                    self.onAnswer?(callID)
                case Identifier.declineAction:
                    self.onDecline?(callID)
                case UNNotificationDefaultActionIdentifier:
                    NSApp.activate(ignoringOtherApps: true)
                    MainWindow.show()
                    self.onShowCall?(callID)
                default:
                    // Dismissing the banner leaves the call ringing
                    break
                }
            }
        }

        completionHandler()
    }
}
