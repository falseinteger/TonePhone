//
//  AudioSettingsView.swift
//  TonePhone
//
//  Audio settings: devices, microphone test and access, ringtone.
//

import AVFoundation
import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var viewModel = AppViewModel.shared
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        Form {
            Section("Devices") {
                AudioDevicePicker(
                    title: "Output",
                    devices: viewModel.outputDevices,
                    selection: viewModel.selectedOutputDevice,
                    defaultName: viewModel.getDefaultOutputDeviceName(),
                    onSelect: viewModel.selectOutputDevice
                )
                AudioDevicePicker(
                    title: "Input",
                    devices: viewModel.inputDevices,
                    selection: viewModel.selectedInputDevice,
                    defaultName: viewModel.getDefaultInputDeviceName(),
                    onSelect: viewModel.selectInputDevice
                )
                LabeledContent("Input level") {
                    MicrophoneLevelMeter()
                }
            }

            Section {
                Toggle("Echo cancellation", isOn: $settings.echoCancellation)
            } footer: {
                Text("Keeps the other person from hearing themselves when you use your Mac’s speakers, and reduces background noise. Changes apply from the next call.")
                    .foregroundStyle(.secondary)
            }

            Section {
                RingtonePickerView(selectedRingtone: $settings.selectedRingtone)
                LabeledContent("Microphone access") {
                    microphoneStatusView
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            viewModel.refreshAudioDevices()
            microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    @ViewBuilder
    private var microphoneStatusView: some View {
        switch microphoneStatus {
        case .authorized:
            Text("Allowed")
                .foregroundStyle(.secondary)
        case .notDetermined:
            Button("Allow Access…") {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async {
                        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    }
                }
            }
        default:
            HStack {
                Label("Not Allowed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Button("Open System Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

/// Pop-up button for choosing an audio device, with System Default first.
struct AudioDevicePicker: View {
    let title: String
    let devices: [AudioDevice]
    let selection: AudioDevice?
    let defaultName: String?
    let onSelect: (AudioDevice?) -> Void

    var body: some View {
        Picker(title, selection: Binding(
            get: { selection?.id ?? "" },
            set: { id in onSelect(devices.first { $0.id == id }) }
        )) {
            Text(defaultName.map { "System Default (\($0))" } ?? "System Default").tag("")
            if !devices.isEmpty {
                Divider()
            }
            ForEach(devices) { device in
                Text(device.name).tag(device.id)
            }
        }
    }
}

#Preview("Audio Settings") {
    AudioSettingsView()
}
