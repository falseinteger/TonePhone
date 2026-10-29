//
//  DiagnosticsSettingsView.swift
//  TonePhone
//
//  Diagnostics settings: log level, SIP message logging, logs.
//

import SwiftUI

struct DiagnosticsSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
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
            } footer: {
                Text(settings.advancedMode
                     ? "SIP messages include phone numbers, addresses and call encryption keys, but never passwords. Turn this off when you’re done troubleshooting."
                     : "Turn on to view the connection log and record SIP messages for troubleshooting.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Diagnostics Settings") {
    DiagnosticsSettingsView()
}
