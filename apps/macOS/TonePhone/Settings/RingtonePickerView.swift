//
//  RingtonePickerView.swift
//  TonePhone
//
//  Ringtone selection with preview playback.
//

import AVFoundation
import SwiftUI

/// A ringtone entry with file info.
private struct Ringtone: Identifiable {
    let id: String  // filename
    let name: String  // display name (without .aiff)
    let path: String
}

struct RingtonePickerView: View {
    @Binding var selectedRingtone: String
    @State private var ringtones: [Ringtone] = []
    @State private var playingID: String?
    @State private var player: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ringtones) { ringtone in
                HStack(spacing: 10) {
                    Image(systemName: selectedRingtone == ringtone.id ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedRingtone == ringtone.id ? .accentColor : .secondary)

                    Text(ringtone.name)
                        .font(.system(size: 13))

                    Spacer()

                    Button {
                        togglePreview(ringtone)
                    } label: {
                        Image(systemName: playingID == ringtone.id ? "stop.fill" : "play.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
                    .accessibilityLabel(playingID == ringtone.id ? "Stop \(ringtone.name)" : "Preview \(ringtone.name)")
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedRingtone == ringtone.id ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    stopPreview()
                    selectedRingtone = ringtone.id
                }
            }
        }
        .onAppear { loadRingtones() }
        .onDisappear { stopPreview() }
    }

    private func loadRingtones() {
        let dir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }

        ringtones = files
            .filter { $0.hasSuffix(".aiff") }
            .sorted()
            .map { filename in
                Ringtone(
                    id: filename,
                    name: String(filename.dropLast(5)),
                    path: "\(dir)/\(filename)"
                )
            }
    }

    private func togglePreview(_ ringtone: Ringtone) {
        if playingID == ringtone.id {
            stopPreview()
        } else {
            stopPreview()
            do {
                player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: ringtone.path))
                player?.volume = 0.7
                player?.play()
                playingID = ringtone.id

                let duration = player?.duration ?? 2.0
                let expectedID = ringtone.id
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    if playingID == expectedID {
                        playingID = nil
                    }
                }
            } catch {
                // Silently fail — preview is non-critical
            }
        }
    }

    private func stopPreview() {
        player?.stop()
        player = nil
        playingID = nil
    }
}

#Preview("Ringtone Picker") {
    struct Wrapper: View {
        @State private var selected = "Ping.aiff"
        var body: some View {
            RingtonePickerView(selectedRingtone: $selected)
                .padding()
                .frame(width: 300)
        }
    }
    return Wrapper()
}
