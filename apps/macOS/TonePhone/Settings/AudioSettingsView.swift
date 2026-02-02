//
//  AudioSettingsView.swift
//  TonePhone
//
//  Audio settings: input/output device selection, mic test, ringtone.
//

import AVFoundation
import CoreAudio
import SwiftUI

/// Simple audio device info for display in settings.
private struct AudioDeviceInfo: Identifiable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool
}

struct AudioSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var inputDevices: [AudioDeviceInfo] = []
    @State private var outputDevices: [AudioDeviceInfo] = []
    @State private var selectedInputID: AudioDeviceID = 0
    @State private var selectedOutputID: AudioDeviceID = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Audio")
                    .font(.title2)
                    .fontWeight(.bold)

                // Output
                SettingsSection(title: "Output Device") {
                    deviceList(devices: outputDevices, selectedID: $selectedOutputID)
                }

                // Input
                SettingsSection(title: "Input Device") {
                    deviceList(devices: inputDevices, selectedID: $selectedInputID)
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
        .onAppear { loadDevices() }
    }

    // MARK: - Device List

    @ViewBuilder
    private func deviceList(devices: [AudioDeviceInfo], selectedID: Binding<AudioDeviceID>) -> some View {
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
                    setAudioDevice(id: device.id, forInput: inputDevices.contains(where: { $0.id == device.id }))
                }
            }
        }
    }

    // MARK: - Load Devices

    private func loadDevices() {
        outputDevices = enumerateDevices(forInput: false)
        inputDevices = enumerateDevices(forInput: true)

        // Select defaults
        selectedOutputID = outputDevices.first(where: \.isDefault)?.id ?? 0
        selectedInputID = inputDevices.first(where: \.isDefault)?.id ?? 0
    }

    private func setAudioDevice(id: AudioDeviceID, forInput: Bool) {
        var deviceID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: forInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &deviceID)
    }

    private func enumerateDevices(forInput: Bool) -> [AudioDeviceInfo] {
        // Get default device
        var defaultID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: forInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultID)

        // Get all devices
        addr.mSelector = kAudioHardwarePropertyDevices
        var listSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &listSize)

        let count = Int(listSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &listSize, &ids)

        var result: [AudioDeviceInfo] = []
        for deviceID in ids {
            // Check if device has input/output streams
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: forInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }

            // Get name
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &cfName)

            result.append(AudioDeviceInfo(
                id: deviceID,
                name: cfName as String,
                isDefault: deviceID == defaultID
            ))
        }

        return result.sorted { $0.isDefault && !$1.isDefault }
    }
}

#Preview("Audio Settings") {
    AudioSettingsView()
        .frame(width: 500, height: 600)
}
