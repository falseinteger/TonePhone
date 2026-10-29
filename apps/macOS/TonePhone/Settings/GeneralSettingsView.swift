//
//  GeneralSettingsView.swift
//  TonePhone
//
//  General settings: startup, phone number formats, notifications.
//

import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var notificationsAllowed: Bool?

    /// Region codes for the picker, sorted by localized name.
    private static let regionOptions: [(code: String, name: String)] = {
        let locale = Locale.current
        return Locale.Region.isoRegions.map(\.identifier).compactMap { code in
            guard let name = locale.localizedString(forRegionCode: code) else { return nil }
            return (code: code, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// A sample number shown in both formats so the effect of the settings is visible.
    private var sampleNumber: String {
        switch PhoneNumberService.region {
        case "GB": return "+442079460018"
        case "DE": return "+4930901820"
        case "FR": return "+33142685300"
        case "RU": return "+74951234567"
        case "AU": return "+61291234567"
        default: return "+14155550123"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Connect automatically when TonePhone opens", isOn: $settings.registerOnStartup)
            } header: {
                Text("Startup")
            } footer: {
                Text("Connects the account marked “Connect automatically” in its settings.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Region", selection: $settings.phoneNumberRegion) {
                    Text("System Default").tag("")
                    Divider()
                    ForEach(Self.regionOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }

                Picker("Show numbers as", selection: $settings.phoneNumberDisplayFormat) {
                    ForEach(PhoneNumberDisplayFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("Dial numbers as", selection: $settings.phoneNumberDialFormat) {
                    ForEach(PhoneNumberDialFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                if settings.phoneNumberDialFormat == .internationalPrefix || settings.phoneNumberDialFormat == .national {
                    TextField(
                        "International prefix",
                        text: $settings.internationalPrefix,
                        prompt: Text(PhoneNumberService.defaultInternationalPrefix(for: PhoneNumberService.region))
                    )
                }

                Toggle("Format numbers while typing", isOn: $settings.formatAsYouType)

                LabeledContent("Shown as") {
                    Text(PhoneNumberService.formatForDisplay(sampleNumber))
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                LabeledContent("Dialed as") {
                    Text(PhoneNumberService.dialString(for: sampleNumber))
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            } header: {
                Text("Phone Numbers")
            } footer: {
                Text("The region is used for numbers typed without a country code. Each account can override how numbers are dialed.")
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                LabeledContent("Incoming call alerts") {
                    switch notificationsAllowed {
                    case .some(true):
                        Text("Allowed")
                            .foregroundStyle(.secondary)
                    case .some(false):
                        HStack {
                            Label("Off", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                            Button("Open System Settings…") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    case .none:
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .task { await checkNotifications() }
    }

    @MainActor
    private func checkNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional:
            notificationsAllowed = true
        default:
            notificationsAllowed = false
        }
    }
}

#Preview("General Settings") {
    GeneralSettingsView()
}
