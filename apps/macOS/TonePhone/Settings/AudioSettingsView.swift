//
//  AudioSettingsView.swift
//  TonePhone
//
//  Audio settings: input/output device selection, mic test, ringtone.
//

import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var inputDevices: [AudioDevice] = []
    @State private var outputDevices: [AudioDevice] = []
    @State private var selectedInputID: String = ""
    @State private var selectedOutputID: String = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Audio")
                    .font(.title2)
                    .fontWeight(.bold)

                // Output
                SettingsSection(title: "Output Device") {
                    deviceList(devices: outputDevices, selectedID: $selectedOutputID, forInput: false)
                }

                // Input
                SettingsSection(title: "Input Device") {
                    deviceList(devices: inputDevices, selectedID: $selectedInputID, forInput: true)
                    Divider().padding(.horizontal, 12)

                    SettingsRow(label: "Mic Test") {
                        MicrophoneLevelMeter()
                    }
                }

                // Ringtone
                SettingsSection(title: "Ringtone") {
                    RingtonePickerView(selectedRingtone: $settings.selectedRingtone)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { loadDevices() }
    }

    // MARK: - Device List

    @ViewBuilder
    private func deviceList(devices: [AudioDevice], selectedID: Binding<String>, forInput: Bool) -> some View {
        if devices.isEmpty {
            Text("No devices found")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            ForEach(devices) { device in
                let isSelected = device.id == selectedID.wrappedValue
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                            .font(.system(size: 13))

                        if device.isDefault {
                            Text("System Default")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedID.wrappedValue = device.id
                    setAudioDevice(device, forInput: forInput)
                }
            }
        }
    }

    // MARK: - Load Devices

    private func loadDevices() {
        let core = TonePhoneCore.shared
        outputDevices = core.getOutputDevices()
        inputDevices = core.getInputDevices()

        // Select defaults
        selectedOutputID = outputDevices.first(where: \.isDefault)?.id ?? ""
        selectedInputID = inputDevices.first(where: \.isDefault)?.id ?? ""
    }

    private func setAudioDevice(_ device: AudioDevice, forInput: Bool) {
        errorMessage = nil
        do {
            if forInput {
                try TonePhoneCore.shared.setInputDevice(device)
            } else {
                try TonePhoneCore.shared.setOutputDevice(device)
            }
        } catch {
            errorMessage = "Failed to set \(forInput ? "input" : "output") device: \(error.localizedDescription)"
        }
    }
}

#Preview("Audio Settings") {
    AudioSettingsView()
        .frame(width: 500, height: 600)
}
