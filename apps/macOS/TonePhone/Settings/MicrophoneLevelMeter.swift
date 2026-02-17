//
//  MicrophoneLevelMeter.swift
//  TonePhone
//
//  Real-time audio level display for microphone testing.
//

import AVFoundation
import SwiftUI

/// Monitors microphone audio levels using AVAudioEngine.
@MainActor
final class MicrophoneLevelMonitor: ObservableObject {
    @Published private(set) var level: Float = 0.0
    @Published private(set) var isMonitoring = false
    @Published private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var isStarting = false

    func startMonitoring() {
        guard !isMonitoring, !isStarting else { return }
        isStarting = true

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.setupAudioEngine()
                } else {
                    self.errorMessage = "Microphone access denied"
                }
                self.isStarting = false
            }
        }
    }

    func stopMonitoring() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isMonitoring = false
        level = 0.0
    }

    private func setupAudioEngine() {
        do {
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "No audio input device available"
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                let channelCount = Int(buffer.format.channelCount)
                guard frameLength > 0, channelCount > 0 else { return }

                var totalSum: Float = 0
                for ch in 0..<channelCount {
                    let samples = channelData[ch]
                    for i in 0..<frameLength {
                        totalSum += samples[i] * samples[i]
                    }
                }
                let rms = sqrt(totalSum / Float(frameLength * channelCount))
                let scaledLevel = min(1.0, rms * 5.0)

                Task { @MainActor in
                    self?.level = (self?.level ?? 0) * 0.3 + scaledLevel * 0.7
                }
            }

            try engine.start()
            audioEngine = engine
            isMonitoring = true
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start audio: \(error.localizedDescription)"
        }
    }
}

/// Visual meter showing the current microphone input level.
struct MicrophoneLevelMeter: View {
    @StateObject private var monitor = MicrophoneLevelMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Level bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .separatorColor))

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [.green, .yellow, .orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * CGFloat(monitor.level)))
                            .animation(.linear(duration: 0.05), value: monitor.level)
                    }
                }
                .frame(height: 8)
                .frame(maxWidth: 200)

                Button(monitor.isMonitoring ? "Stop" : "Test Mic") {
                    if monitor.isMonitoring {
                        monitor.stopMonitoring()
                    } else {
                        monitor.startMonitoring()
                    }
                }
                .buttonStyle(.bordered)
            }

            if let error = monitor.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }
}

#Preview("Microphone Level Meter") {
    MicrophoneLevelMeter()
        .padding()
        .frame(width: 350)
}
