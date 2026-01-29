//
//  AboutSettingsView.swift
//  TonePhone
//
//  About view: version and licenses.
//

import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // App header
                appHeader

                // Version
                SettingsSection(title: "Version") {
                    versionRow("App Version", appVersion)
                    Divider().padding(.horizontal, 12)
                    versionRow("Build", buildNumber)
                    Divider().padding(.horizontal, 12)
                    versionRow("macOS", macOSVersion)
                }

                // Licenses
                SettingsSection(title: "Open Source Licenses") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TonePhone is open source software licensed under the MIT License.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        licenseRow("baresip", "BSD-3-Clause")
                        licenseRow("libre", "BSD-3-Clause")
                        licenseRow("OpenSSL", "Apache-2.0")
                        licenseRow("Opus", "BSD-3-Clause")
                    }
                    .padding(12)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - App Header

    private var appHeader: some View {
        HStack(spacing: 16) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(12)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TonePhone")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("A simple SIP softphone")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Rows

    private func versionRow(_ label: String, _ value: String) -> some View {
        SettingsRow(label: label) {
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private func licenseRow(_ name: String, _ license: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(license)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Computed

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

#Preview("About Settings") {
    AboutSettingsView()
        .frame(width: 500, height: 400)
}
