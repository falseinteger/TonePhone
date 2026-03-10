//
//  GeneralSettingsView.swift
//  TonePhone
//
//  General settings: appearance, startup, default transport.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    /// Common region codes for the picker, sorted by display name.
    private static let regionOptions: [(code: String, name: String)] = {
        let codes = Locale.Region.isoRegions.map(\.identifier)
        let locale = Locale.current
        return codes.compactMap { code in
            guard let name = locale.localizedString(forRegionCode: code) else { return nil }
            return (code: code, name: "\(name) (\(code))")
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("General")
                    .font(.title2)
                    .fontWeight(.bold)

                // Appearance
                SettingsSection(title: "Appearance") {
                    Picker("", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                // Phone Number
                SettingsSection(title: "Phone Numbers") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Region")
                                .font(.system(size: 13))
                                .foregroundColor(.primary)

                            Text("Used for phone number formatting and dialing")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $settings.phoneNumberRegion) {
                            Text("System Default").tag("")
                            Divider()
                            ForEach(Self.regionOptions, id: \.code) { option in
                                Text(option.name).tag(option.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                // Startup
                SettingsSection(title: "Startup") {
                    SettingsToggle(
                        label: "Connect on Startup",
                        description: "Automatically connect accounts when app launches",
                        isOn: $settings.registerOnStartup
                    )
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("General Settings") {
    GeneralSettingsView()
        .frame(width: 500, height: 400)
}
