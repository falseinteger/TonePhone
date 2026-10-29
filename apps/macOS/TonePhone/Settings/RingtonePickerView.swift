//
//  RingtonePickerView.swift
//  TonePhone
//
//  Ringtone pop-up button with a preview button.
//

import AVFoundation
import SwiftUI

struct RingtonePickerView: View {
    @Binding var selectedRingtone: String
    @State private var ringtones: [String] = []
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    private static let soundsDirectory = "/System/Library/Sounds"

    var body: some View {
        LabeledContent("Ringtone") {
            HStack {
                Picker("Ringtone", selection: $selectedRingtone) {
                    ForEach(ringtones, id: \.self) { file in
                        Text(Self.displayName(for: file)).tag(file)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Button {
                    isPlaying ? stopPreview() : startPreview()
                } label: {
                    Label(isPlaying ? "Stop" : "Play", systemImage: isPlaying ? "stop.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                }
                .help(isPlaying ? "Stop preview" : "Play ringtone")
            }
        }
        .onAppear { loadRingtones() }
        .onDisappear { stopPreview() }
        .onChange(of: selectedRingtone) { _ in
            if isPlaying { startPreview() }
        }
    }

    private static func displayName(for file: String) -> String {
        (file as NSString).deletingPathExtension
    }

    private func loadRingtones() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.soundsDirectory)) ?? []
        ringtones = files.filter { $0.hasSuffix(".aiff") }.sorted()
        if !ringtones.contains(selectedRingtone), let first = ringtones.first {
            ringtones.insert(selectedRingtone, at: 0)
            if !FileManager.default.fileExists(atPath: "\(Self.soundsDirectory)/\(selectedRingtone)") {
                ringtones.removeFirst()
                selectedRingtone = first
            }
        }
    }

    private func startPreview() {
        stopPreview()
        let url = URL(fileURLWithPath: "\(Self.soundsDirectory)/\(selectedRingtone)")
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        newPlayer.volume = 0.7
        newPlayer.numberOfLoops = 2
        newPlayer.play()
        player = newPlayer
        isPlaying = true

        let duration = newPlayer.duration * 3
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak newPlayer] in
            if newPlayer != nil, player === newPlayer {
                stopPreview()
            }
        }
    }

    private func stopPreview() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}
