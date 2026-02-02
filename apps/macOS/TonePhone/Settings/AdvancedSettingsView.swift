//
//  AdvancedSettingsView.swift
//  TonePhone
//
//  Advanced settings: STUN servers, NAT, DTMF, diagnostics.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Advanced")
                    .font(.title2)
                    .fontWeight(.bold)

                // NAT Traversal
                SettingsSection(title: "NAT Traversal") {
                    stunServersRow
                    Divider().padding(.horizontal, 12)

                    SettingsRow(label: "NAT Method") {
                        Picker("", selection: $settings.natMethod) {
                            ForEach(NATMethod.allCases, id: \.self) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .frame(width: 120)
                    }
                    Divider().padding(.horizontal, 12)

                    SettingsToggle(
                        label: "NAT Pinhole",
                        description: "Send keep-alive packets to maintain NAT mappings",
                        isOn: $settings.natPinhole
                    )
                }

                // SIP
                SettingsSection(title: "SIP") {
                    SettingsRow(label: "DTMF Mode") {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("", selection: $settings.dtmfMode) {
                                ForEach(DTMFMode.allCases, id: \.self) { m in
                                    Text(m.displayName).tag(m)
                                }
                            }
                            .frame(width: 120)

                            Text(settings.dtmfMode.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Divider().padding(.horizontal, 12)

                    SettingsToggle(
                        label: "RTCP Feedback",
                        description: "Enable RTCP feedback for media quality reporting",
                        isOn: $settings.rtcpFeedback
                    )
                }

                // Diagnostics
                SettingsSection(title: "Diagnostics") {
                    SettingsRow(label: "Log Level") {
                        Picker("", selection: $settings.logLevel) {
                            Text("Error").tag(LogLevel.error)
                            Text("Warning").tag(LogLevel.warning)
                            Text("Info").tag(LogLevel.info)
                            Text("Debug").tag(LogLevel.debug)
                            Text("Trace").tag(LogLevel.trace)
                        }
                        .frame(width: 120)
                    }
                    Divider().padding(.horizontal, 12)

                    logFileRow
                    Divider().padding(.horizontal, 12)
                    exportRow
                }

                // Reset
                HStack {
                    Spacer()
                    Button("Reset All Settings to Defaults") {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - STUN Servers

    private var stunServersRow: some View {
        HStack(alignment: .top) {
            Text("STUN Servers")
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .trailing)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                STUNServerListEditor(servers: $settings.stunServers)

                Text("STUN servers help establish connections through NAT")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Log File

    private var logFileRow: some View {
        SettingsRow(label: "Log File") {
            if let logPath = TonePhoneCore.shared.getLogFilePath() {
                HStack(spacing: 8) {
                    Text(logPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        let url = URL(fileURLWithPath: logPath)
                        NSWorkspace.shared.selectFile(
                            url.path,
                            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
                        )
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
            } else {
                Text("Not available")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Export

    private var exportRow: some View {
        SettingsRow(label: "Export") {
            Button("Export Logs\u{2026}") {
                exportLogs()
            }
            .buttonStyle(.bordered)
        }
    }

    private func exportLogs() {
        guard let logPath = TonePhoneCore.shared.getLogFilePath() else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tonephone-logs.txt"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: URL(fileURLWithPath: logPath))
            } else {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: logPath), to: url)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

#Preview("Advanced Settings") {
    AdvancedSettingsView()
        .frame(width: 500, height: 600)
}
