//
//  AudioDevicePickerView.swift
//  TonePhone
//
//  Menu for choosing the audio output and input during a call.
//

import SwiftUI

/// Toolbar-style menu with the output and input device choices.
struct AudioDeviceMenu: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Menu {
            Picker("Output", selection: Binding(
                get: { viewModel.selectedOutputDevice?.id ?? "" },
                set: { id in viewModel.selectOutputDevice(viewModel.outputDevices.first { $0.id == id }) }
            )) {
                Text(defaultTitle(viewModel.getDefaultOutputDeviceName())).tag("")
                ForEach(viewModel.outputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .pickerStyle(.inline)

            Picker("Input", selection: Binding(
                get: { viewModel.selectedInputDevice?.id ?? "" },
                set: { id in viewModel.selectInputDevice(viewModel.inputDevices.first { $0.id == id }) }
            )) {
                Text(defaultTitle(viewModel.getDefaultInputDeviceName())).tag("")
                ForEach(viewModel.inputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Audio Devices", systemImage: "speaker.wave.2")
        }
        .help("Choose speaker and microphone")
        .onAppear { viewModel.refreshAudioDevices() }
    }

    private func defaultTitle(_ name: String?) -> String {
        name.map { "System Default (\($0))" } ?? "System Default"
    }
}
