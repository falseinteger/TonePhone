//
//  AdvancedSettingsView.swift
//  TonePhone
//
//  Advanced settings: NAT traversal, SIP, security, diagnostics.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var showResetConfirmation = false

    private func importCertificates() {
        let panel = NSOpenPanel()
        panel.message = "Choose a certificate file in PEM format."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.x509Certificate, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.importAdditionalCertificates(from: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("STUN servers") {
                    STUNServerListEditor(servers: $settings.stunServers)
                }

                Picker("NAT traversal", selection: $settings.natMethod) {
                    ForEach(NATMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }

                Toggle("Keep NAT mappings open", isOn: $settings.natPinhole)
            } header: {
                Text("Network")
            } footer: {
                Text("\(settings.natMethod.description). Accounts can override these settings.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Keypad tones", selection: $settings.dtmfMode) {
                    ForEach(DTMFMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Default transport", selection: $settings.defaultTransport) {
                    ForEach(SIPTransport.allCases, id: \.self) { transport in
                        Text(transport.displayName).tag(transport)
                    }
                }

                Toggle("Verify server certificates (TLS)", isOn: $settings.verifyTLSServer)

                LabeledContent("Trusted certificates") {
                    HStack {
                        Text(settings.additionalCAFile == nil ? "System only" : "System and imported")
                            .foregroundStyle(.secondary)
                        if settings.additionalCAFile != nil {
                            Button("Remove") {
                                settings.removeAdditionalCertificates()
                            }
                        }
                        Button("Import…") {
                            importCertificates()
                        }
                    }
                }
            } header: {
                Text("SIP")
            } footer: {
                Text(settings.dtmfMode.description + " Import a certificate if your provider uses its own certificate authority. Certificate changes take effect the next time TonePhone opens.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show diagnostics", isOn: $settings.advancedMode)

                Picker("Log level", selection: $settings.logLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.name).tag(level)
                    }
                }

                if settings.advancedMode {
                    Toggle("Log SIP messages", isOn: $settings.sipTrace)

                    LabeledContent("Logs") {
                        HStack {
                            Button("Show Logs") {
                                openWindow(id: LogViewerView.windowID)
                            }
                            Button("Export Logs…") {
                                LogExporter.export()
                            }
                        }
                    }
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text(settings.advancedMode
                     ? "SIP messages include phone numbers and addresses but never passwords. Turn this off when you’re done troubleshooting."
                     : "Turn on to view the connection log and record SIP messages for troubleshooting.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…") {
                    showResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("Your accounts and call history are kept.")
        }
    }
}

#Preview("Advanced Settings") {
    AdvancedSettingsView()
}
