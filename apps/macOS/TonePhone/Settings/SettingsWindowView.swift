//
//  SettingsWindowView.swift
//  TonePhone
//
//  Apple System Settings style window with sidebar navigation.
//

import SwiftUI

extension Notification.Name {
    static let showAboutSettings = Notification.Name("com.tonephone.showAboutSettings")
    static let showLicensesSettings = Notification.Name("com.tonephone.showLicensesSettings")
    static let accountSettingsChanged = Notification.Name("com.tonephone.accountSettingsChanged")
}

/// Settings category for sidebar navigation.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case audio
    case accounts
    case permissions
    case advanced
    case about
    case licenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .audio: return "Audio"
        case .accounts: return "Accounts"
        case .permissions: return "Permissions"
        case .advanced: return "Advanced"
        case .about: return "About"
        case .licenses: return "Licenses"
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
        case .licenses: return "doc.text"
        }
    }
}

/// Main settings window view with Apple System Settings style sidebar navigation.
struct SettingsWindowView: View {
    /// Pending category to select when the window appears (set before opening).
    static var pendingCategory: SettingsCategory?

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
        .onAppear {
            if let pending = Self.pendingCategory {
                selectedCategory = pending
                Self.pendingCategory = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutSettings)) { _ in
            selectedCategory = .about
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLicensesSettings)) { _ in
            selectedCategory = .licenses
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
            case .licenses:
                LicensesSettingsView()
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
