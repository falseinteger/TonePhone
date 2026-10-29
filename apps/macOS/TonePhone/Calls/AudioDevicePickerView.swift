//
//  AudioDevicePickerView.swift
//  TonePhone
//
//  Speaker and microphone choice during a call.
//

import SwiftUI

/// Round "Audio" button in the call window; opens the speaker and
/// microphone choices. The same choices are in the Call menu.
struct AudioDeviceMenu: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isPresented = false

    var body: some View {
        CircleActionButton(title: "Audio", systemImage: "speaker.wave.2.fill", tint: nil, isOn: isPresented) {
            isPresented.toggle()
        }
        .help("Choose speaker and microphone")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Form {
                Picker("Speaker", selection: Binding(
                    get: { viewModel.selectedOutputDevice?.id ?? "" },
                    set: { id in viewModel.selectOutputDevice(viewModel.outputDevices.first { $0.id == id }) }
                )) {
                    Text(defaultTitle(viewModel.getDefaultOutputDeviceName())).tag("")
                    ForEach(viewModel.outputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }

                Picker("Microphone", selection: Binding(
                    get: { viewModel.selectedInputDevice?.id ?? "" },
                    set: { id in viewModel.selectInputDevice(viewModel.inputDevices.first { $0.id == id }) }
                )) {
                    Text(defaultTitle(viewModel.getDefaultInputDeviceName())).tag("")
                    ForEach(viewModel.inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            }
            .padding(16)
            .frame(width: 340)
            .onAppear { viewModel.refreshAudioDevices() }
        }
    }

    private func defaultTitle(_ name: String?) -> String {
        name.map { "System Default (\($0))" } ?? "System Default"
    }
}
