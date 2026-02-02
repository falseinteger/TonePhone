//
//  PermissionsSettingsView.swift
//  TonePhone
//
//  Permissions status: microphone, notifications.
//

import AVFoundation
import SwiftUI
import UserNotifications

struct PermissionsSettingsView: View {
    @State private var micStatus: PermissionStatus = .checking
    @State private var notifStatus: PermissionStatus = .checking

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Permissions")
                    .font(.title2)
                    .fontWeight(.bold)

                SettingsSection(title: "Required Permissions") {
                    permissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Required for voice calls",
                        status: micStatus,
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                        onRequest: requestMicrophone
                    )
                    Divider().padding(.horizontal, 12)
                    permissionRow(
                        icon: "bell.fill",
                        title: "Notifications",
                        description: "Used for incoming call alerts",
                        status: notifStatus,
                        settingsURL: "x-apple.systempreferences:com.apple.preference.notifications",
                        onRequest: requestNotifications
                    )
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await checkPermissions() }
    }

    // MARK: - Permission Row

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        status: PermissionStatus,
        settingsURL: String,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if status == .notRequested {
                Button("Request Access") {
                    onRequest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if status == .denied {
                Button("Open System Settings") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Request

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                micStatus = granted ? .granted : .denied
            }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                notifStatus = granted ? .granted : .denied
            }
        }
    }

    // MARK: - Status

    private enum PermissionStatus: Equatable {
        case checking
        case granted
        case denied
        case notRequested

        var label: String {
            switch self {
            case .checking: return "Checking\u{2026}"
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .notRequested: return "Not Requested"
            }
        }

        var color: Color {
            switch self {
            case .checking: return .secondary
            case .granted: return .green
            case .denied: return .red
            case .notRequested: return .orange
            }
        }
    }

    // MARK: - Check

    private func checkPermissions() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micStatus = .granted
        case .denied, .restricted: micStatus = .denied
        case .notDetermined: micStatus = .notRequested
        @unknown default: micStatus = .notRequested
        }

        let notifSettings = await UNUserNotificationCenter.current().notificationSettings()
        switch notifSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notifStatus = .granted
        case .denied: notifStatus = .denied
        case .notDetermined: notifStatus = .notRequested
        @unknown default: notifStatus = .notRequested
        }
    }
}

#Preview("Permissions Settings") {
    PermissionsSettingsView()
        .frame(width: 500, height: 350)
}
