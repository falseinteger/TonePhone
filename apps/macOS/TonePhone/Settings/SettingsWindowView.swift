//
//  SettingsWindowView.swift
//  TonePhone
//
//  Settings window with toolbar panes, as the macOS HIG describes for app settings.
//

import SwiftUI

extension Notification.Name {
    static let accountSettingsChanged = Notification.Name("com.tonephone.accountSettingsChanged")
}

/// A pane in the Settings window.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case accounts
    case audio
    case advanced

    var id: String { rawValue }
}

/// The Settings window. Each pane is a toolbar item; the window title
/// follows the selected pane and the last pane is restored on reopen.
struct SettingsWindowView: View {
    @AppStorage("settings.selectedPane") private var selectedPane: SettingsPane = .general

    var body: some View {
        TabView(selection: $selectedPane) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsPane.general)

            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "at") }
                .tag(SettingsPane.accounts)

            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
                .tag(SettingsPane.audio)

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(SettingsPane.advanced)
        }
        .frame(width: 540)
    }
}

#Preview("Settings Window") {
    SettingsWindowView()
}
