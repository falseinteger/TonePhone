//
//  SettingsView.swift
//  TonePhone
//
//  SwiftUI sheet for app settings with Basic and Advanced modes.
//

import SwiftUI

/// Settings mode toggle.
enum SettingsMode: String, CaseIterable {
    case basic = "Basic"
    case advanced = "Advanced"
}

/// View for configuring app settings.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsStore.shared

    @State private var mode: SettingsMode = .basic

    // Local copies for editing (allows cancel without saving)
    @State private var logLevel: LogLevel = .info
    @State private var defaultTransport: SIPTransport = .udp
    @State private var stunServer: String = ""
    @State private var natMethod: NATMethod = .stun
    @State private var natPinhole: Bool = true
    @State private var dtmfMode: DTMFMode = .rfc2833
    @State private var rtcpFeedback: Bool = true
    @State private var registerOnStartup: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Form content
            ScrollView {
                VStack(spacing: 24) {
                    if mode == .basic {
                        basicSettings
                    } else {
                        advancedSettings
                    }
                }
                .padding(.vertical, 20)
            }

            Divider()

            // Footer buttons
            footerView
        }
        .frame(width: 440, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadSettings()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.headline)

                Text("Configure TonePhone preferences")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Mode toggle
            Picker("", selection: $mode) {
                ForEach(SettingsMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Basic Settings

    private var basicSettings: some View {
        VStack(spacing: 24) {
            // General section
            SettingsSection(title: "General") {
                SettingsToggle(
                    label: "Connect on Startup",
                    description: "Automatically connect accounts when app launches",
                    isOn: $registerOnStartup
                )
            }

            // Logging section
            SettingsSection(title: "Logging") {
                SettingsRow(label: "Log Level") {
                    Picker("", selection: $logLevel) {
                        Text("Error").tag(LogLevel.error)
                        Text("Warning").tag(LogLevel.warning)
                        Text("Info").tag(LogLevel.info)
                        Text("Debug").tag(LogLevel.debug)
                        Text("Trace").tag(LogLevel.trace)
                    }
                    .frame(width: 120)
                }
            }

            // Account Defaults section
            SettingsSection(title: "Account Defaults") {
                SettingsRow(label: "Transport") {
                    Picker("", selection: $defaultTransport) {
                        ForEach(SIPTransport.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
    }

    // MARK: - Advanced Settings

    private var advancedSettings: some View {
        VStack(spacing: 24) {
            // NAT Traversal section
            SettingsSection(title: "NAT Traversal") {
                SettingsTextField(
                    label: "STUN Server",
                    placeholder: "stun:stun.l.google.com:19302",
                    text: $stunServer
                )

                SettingsRow(label: "NAT Method") {
                    Picker("", selection: $natMethod) {
                        ForEach(NATMethod.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .frame(width: 120)
                }

                SettingsToggle(
                    label: "NAT Pinhole",
                    description: "Send keep-alive packets to maintain NAT mappings",
                    isOn: $natPinhole
                )
            }

            // Audio section
            SettingsSection(title: "Audio") {
                SettingsRow(label: "DTMF Mode") {
                    Picker("", selection: $dtmfMode) {
                        ForEach(DTMFMode.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .frame(width: 120)
                }

                SettingsToggle(
                    label: "RTCP Feedback",
                    description: "Enable RTCP feedback for media quality reporting",
                    isOn: $rtcpFeedback
                )
            }

            // Logging section (also in advanced for accessibility)
            SettingsSection(title: "Diagnostics") {
                SettingsRow(label: "Log Level") {
                    Picker("", selection: $logLevel) {
                        Text("Error").tag(LogLevel.error)
                        Text("Warning").tag(LogLevel.warning)
                        Text("Info").tag(LogLevel.info)
                        Text("Debug").tag(LogLevel.debug)
                        Text("Trace").tag(LogLevel.trace)
                    }
                    .frame(width: 120)
                }

                if let logPath = TonePhoneCore.shared.getLogFilePath() {
                    SettingsRow(label: "Log File") {
                        Text(logPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            Button("Reset to Defaults") {
                resetToDefaults()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button("Save") {
                saveSettings()
                dismiss()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func loadSettings() {
        logLevel = settings.logLevel
        defaultTransport = settings.defaultTransport
        stunServer = settings.stunServer
        natMethod = settings.natMethod
        natPinhole = settings.natPinhole
        dtmfMode = settings.dtmfMode
        rtcpFeedback = settings.rtcpFeedback
        registerOnStartup = settings.registerOnStartup
    }

    private func saveSettings() {
        settings.logLevel = logLevel
        settings.defaultTransport = defaultTransport
        settings.stunServer = stunServer
        settings.natMethod = natMethod
        settings.natPinhole = natPinhole
        settings.dtmfMode = dtmfMode
        settings.rtcpFeedback = rtcpFeedback
        settings.registerOnStartup = registerOnStartup
    }

    private func resetToDefaults() {
        logLevel = .info
        defaultTransport = .udp
        stunServer = "stun:stun.l.google.com:19302"
        natMethod = .stun
        natPinhole = true
        dtmfMode = .rfc2833
        rtcpFeedback = true
        registerOnStartup = true
    }
}

// MARK: - Settings Form Components

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 20)
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SettingsRow(label: label) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
    }
}

private struct SettingsToggle: View {
    let label: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview("Settings - Basic") {
    SettingsView()
}
