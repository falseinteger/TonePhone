//
//  SettingsWindowView.swift
//  TonePhone
//
//  Apple System Settings style window with sidebar navigation.
//

import SwiftUI

extension Notification.Name {
    static let showAboutSettings = Notification.Name("showAboutSettings")
    static let accountSettingsChanged = Notification.Name("accountSettingsChanged")
}

/// Settings category for sidebar navigation.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case audio
    case accounts
    case permissions
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .audio: return "Audio"
        case .accounts: return "Accounts"
        case .permissions: return "Permissions"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .audio: return "speaker.wave.2"
        case .accounts: return "person.2"
        case .permissions: return "hand.raised"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

/// Main settings window view with Apple System Settings style sidebar navigation.
struct SettingsWindowView: View {
    @State private var selectedCategory: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 650, minHeight: 450)
        .frame(idealWidth: 750, idealHeight: 550)
        .toolbar(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: .showAboutSettings)) { _ in
            selectedCategory = .about
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SettingsCategory.allCases, selection: $selectedCategory) { category in
            Label {
                Text(category.title)
            } icon: {
                Image(systemName: category.icon)
                    .foregroundColor(.accentColor)
            }
            .tag(category)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let category = selectedCategory {
            switch category {
            case .general:
                GeneralSettingsView()
            case .audio:
                AudioSettingsView()
            case .accounts:
                AccountsSettingsView()
            case .permissions:
                PermissionsSettingsView()
            case .advanced:
                AdvancedSettingsView()
            case .about:
                AboutSettingsView()
            }
        } else {
            Text("Select a category")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview("Settings Window") {
    SettingsWindowView()
}
