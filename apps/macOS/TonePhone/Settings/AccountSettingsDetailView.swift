//
//  AccountSettingsDetailView.swift
//  TonePhone
//
//  Per-account advanced settings overrides (shown as sheet).
//

import SwiftUI

struct AccountSettingsDetailView: View {
    let account: SIPAccount
    let onSave: (SIPAccount) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var globalSettings = SettingsStore.shared

    // Override toggles
    @State private var useCustomStunServer = false
    @State private var useCustomNatMethod = false
    @State private var useCustomNatPinhole = false
    @State private var useCustomDtmfMode = false

    // Override values
    @State private var stunServerOverride = ""
    @State private var natMethodOverride: NATMethod = .stun
    @State private var natPinholeOverride = true
    @State private var dtmfModeOverride: DTMFMode = .rfc2833

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerView
                    accountInfoSection
                    overridesSection
                }
                .padding(24)
            }

            Divider()
            footerView
        }
        .onAppear { loadOverrides() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Text(account.initials)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName.isEmpty ? account.username : account.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(account.sipURI)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Account Info (read-only)

    private var accountInfoSection: some View {
        SettingsSection(title: "Account Information") {
            infoRow("Server", account.server)
            Divider().padding(.horizontal, 12)
            infoRow("Username", account.username)
            Divider().padding(.horizontal, 12)
            infoRow("Transport", account.transport.displayName)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        SettingsRow(label: label) {
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Overrides

    private var overridesSection: some View {
        SettingsSection(title: "Advanced Overrides") {
            overrideRow(
                label: "STUN Server",
                isEnabled: $useCustomStunServer,
                globalValue: globalSettings.stunServer
            ) {
                TextField("stun:server:port", text: $stunServerOverride)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(!useCustomStunServer)
            }

            Divider().padding(.horizontal, 12)

            overrideRow(
                label: "NAT Method",
                isEnabled: $useCustomNatMethod,
                globalValue: globalSettings.natMethod.displayName
            ) {
                Picker("", selection: $natMethodOverride) {
                    ForEach(NATMethod.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .frame(width: 100)
                .disabled(!useCustomNatMethod)
            }

            Divider().padding(.horizontal, 12)

            overrideRow(
                label: "NAT Pinhole",
                isEnabled: $useCustomNatPinhole,
                globalValue: globalSettings.natPinhole ? "Enabled" : "Disabled"
            ) {
                Toggle("", isOn: $natPinholeOverride)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!useCustomNatPinhole)
            }

            Divider().padding(.horizontal, 12)

            overrideRow(
                label: "DTMF Mode",
                isEnabled: $useCustomDtmfMode,
                globalValue: globalSettings.dtmfMode.displayName
            ) {
                Picker("", selection: $dtmfModeOverride) {
                    ForEach(DTMFMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .frame(width: 100)
                .disabled(!useCustomDtmfMode)
            }
        }
    }

    private func overrideRow<Content: View>(
        label: String,
        isEnabled: Binding<Bool>,
        globalValue: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: isEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel(Text(label))

                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(isEnabled.wrappedValue ? .primary : .secondary)

                Spacer()

                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if !isEnabled.wrappedValue {
                Text("Using global: \(globalValue)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            Button("Clear All") {
                clearOverrides()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button("Save") {
                saveOverrides()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Load / Save

    private func loadOverrides() {
        if let v = account.stunServerOverride {
            stunServerOverride = v
            useCustomStunServer = true
        } else {
            stunServerOverride = globalSettings.stunServer
        }

        if let v = account.natMethodOverride {
            natMethodOverride = v
            useCustomNatMethod = true
        } else {
            natMethodOverride = globalSettings.natMethod
        }

        if let v = account.natPinholeOverride {
            natPinholeOverride = v
            useCustomNatPinhole = true
        } else {
            natPinholeOverride = globalSettings.natPinhole
        }

        if let v = account.dtmfModeOverride {
            dtmfModeOverride = v
            useCustomDtmfMode = true
        } else {
            dtmfModeOverride = globalSettings.dtmfMode
        }
    }

    private func clearOverrides() {
        useCustomStunServer = false
        stunServerOverride = globalSettings.stunServer
        useCustomNatMethod = false
        natMethodOverride = globalSettings.natMethod
        useCustomNatPinhole = false
        natPinholeOverride = globalSettings.natPinhole
        useCustomDtmfMode = false
        dtmfModeOverride = globalSettings.dtmfMode
    }

    private func saveOverrides() {
        var updated = account
        let trimmedStun = stunServerOverride.trimmingCharacters(in: .whitespaces)
        updated.stunServerOverride = useCustomStunServer && !trimmedStun.isEmpty ? trimmedStun : nil
        updated.natMethodOverride = useCustomNatMethod ? natMethodOverride : nil
        updated.natPinholeOverride = useCustomNatPinhole ? natPinholeOverride : nil
        updated.dtmfModeOverride = useCustomDtmfMode ? dtmfModeOverride : nil
        onSave(updated)
        dismiss()
    }
}

#Preview("Account Detail") {
    AccountSettingsDetailView(
        account: SIPAccount(server: "sip.example.com", username: "alice", displayName: "Alice"),
        onSave: { _ in }
    )
    .frame(width: 500, height: 550)
}
