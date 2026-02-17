//
//  AudioSettingsView.swift
//  TonePhone
//
//  Audio settings: input/output device selection, mic test, ringtone.
//

import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var viewModel = AppViewModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Audio")
                    .font(.title2)
                    .fontWeight(.bold)

                // Output
                SettingsSection(title: "Output Device") {
                    deviceList(devices: viewModel.outputDevices, selected: viewModel.selectedOutputDevice, forInput: false)
                }

                // Input
                SettingsSection(title: "Input Device") {
                    deviceList(devices: viewModel.inputDevices, selected: viewModel.selectedInputDevice, forInput: true)
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

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Device List

    @ViewBuilder
    private func deviceList(devices: [AudioDevice], selected: AudioDevice?, forInput: Bool) -> some View {
        if devices.isEmpty {
            Text("No devices found")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            ForEach(devices) { device in
                let isSelected = device.id == selected?.id
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
                    if forInput {
                        viewModel.selectInputDevice(device)
                    } else {
                        viewModel.selectOutputDevice(device)
                    }
                }
            }
        }
    }
}

#Preview("Audio Settings") {
    AudioSettingsView()
        .frame(width: 500, height: 600)
}
