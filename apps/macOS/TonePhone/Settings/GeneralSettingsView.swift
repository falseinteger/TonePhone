//
//  GeneralSettingsView.swift
//  TonePhone
//
//  General settings: appearance, startup, default transport.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

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
