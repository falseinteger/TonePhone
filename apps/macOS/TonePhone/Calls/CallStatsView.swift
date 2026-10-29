//
//  CallStatsView.swift
//  TonePhone
//
//  Diagnostics only: audio statistics of the current call.
//

import SwiftUI

/// Info button for the call window; shown when diagnostics are on.
struct CallStatsButton: View {
    let callID: CallID
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Call Statistics")
        .accessibilityLabel("Call Statistics")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            CallStatsView(callID: callID)
        }
    }
}

/// Codec, packets, loss, jitter and round trip, refreshed every second.
struct CallStatsView: View {
    let callID: CallID

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 0) {
                content(TonePhoneCore.shared.callStats(callID))
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private func content(_ stats: CallStats?) -> some View {
        if let stats {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Codec", stats.codec.map(Self.codecName) ?? "—")
                Divider()
                GridRow {
                    Text("")
                    Text("Sent").foregroundStyle(.secondary)
                    Text("Received").foregroundStyle(.secondary)
                }
                .font(.caption)
                row("Packets", stats.sentPackets.formatted(), stats.receivedPackets.formatted())
                row("Bitrate", Self.kbps(stats.sendBitrate), Self.kbps(stats.receiveBitrate))
                if let rtcp = stats.rtcp {
                    row("Lost", Self.lost(rtcp.sentLost, of: stats.sentPackets),
                        Self.lost(rtcp.receivedLost, of: stats.receivedPackets))
                    row("Jitter", Self.ms(rtcp.sendJitter), Self.ms(rtcp.receiveJitter))
                    Divider()
                    row("Round trip", Self.ms(rtcp.roundTrip))
                }
            }
            .font(.callout.monospacedDigit())
            .textSelection(.enabled)

            if stats.rtcp == nil {
                Text("Loss, jitter and round trip appear once the other side sends a quality report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        } else {
            Text("No audio yet.")
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).gridCellColumns(2)
        }
    }

    private func row(_ title: String, _ sent: String, _ received: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(sent)
            Text(received)
        }
    }

    /// "opus/48000/2" → "Opus · 48 kHz · Stereo"
    static func codecName(_ codec: String) -> String {
        let parts = codec.split(separator: "/")
        guard let name = parts.first else { return codec }
        var result = [name.lowercased() == "opus" ? "Opus" : String(name)]
        if parts.count > 1, let rate = Double(parts[1]) {
            result.append("\((rate / 1000).formatted()) kHz")
        }
        if parts.count > 2 {
            result.append(parts[2] == "2" ? "Stereo" : "Mono")
        }
        return result.joined(separator: " · ")
    }

    static func kbps(_ bitsPerSecond: Int) -> String {
        "\((Double(bitsPerSecond) / 1000).formatted(.number.precision(.fractionLength(1)))) kbit/s"
    }

    static func ms(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }

    /// "3 (0.4%)"; the far end can report a negative count after duplicates.
    static func lost(_ count: Int, of total: Int) -> String {
        guard count > 0, total > 0 else { return "0" }
        let share = Double(count) / Double(count + total)
        return "\(count) (\(share.formatted(.percent.precision(.fractionLength(1)))))"
    }
}
