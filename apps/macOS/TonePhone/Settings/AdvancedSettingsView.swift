//
//  AdvancedSettingsView.swift
//  TonePhone
//
//  Advanced settings: STUN servers, NAT traversal, connection, certificates.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
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
                STUNServerListEditor(servers: $settings.stunServers)
            } header: {
                Text("STUN Servers")
            }

            Section {
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
                Picker("Default transport", selection: $settings.defaultTransport) {
                    ForEach(SIPTransport.allCases, id: \.self) { transport in
                        Text(transport.displayName).tag(transport)
                    }
                }

                Picker("Keypad tones", selection: $settings.dtmfMode) {
                    ForEach(DTMFMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text(settings.dtmfMode.description)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Verify server certificates", isOn: $settings.verifyTLSServer)

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
                Text("Security")
            } footer: {
                Text("Import a certificate if your provider uses its own certificate authority. Changes take effect the next time TonePhone opens.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…") {
                    showResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
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
