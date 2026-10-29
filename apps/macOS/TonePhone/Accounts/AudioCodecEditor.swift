//
//  AudioCodecEditor.swift
//  TonePhone
//
//  Which audio codecs an account offers, and in what order.
//

import SwiftUI

/// "Audio codecs" row in the account editor: the codecs offered and an
/// Edit button that opens the list.
struct AudioCodecsRow: View {
    /// Nil means all codecs in the default order.
    @Binding var codecs: [AudioCodec]?
    @State private var isEditing = false

    private var summary: String {
        guard let codecs else { return "Default" }
        return codecs.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        LabeledContent("Audio codecs") {
            HStack {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button("Edit…") {
                    isEditing = true
                }
                .popover(isPresented: $isEditing, arrowEdge: .trailing) {
                    AudioCodecEditor(codecs: $codecs)
                }
            }
        }
    }
}

/// Codecs with a checkbox each, dragged into the order they are offered in.
struct AudioCodecEditor: View {
    @Binding var codecs: [AudioCodec]?
    /// Row order while the editor is open, so unchecking a codec doesn't
    /// move its row. Disabled codecs start at the end.
    @State private var order: [AudioCodec]

    init(codecs: Binding<[AudioCodec]?>) {
        _codecs = codecs
        let enabled = codecs.wrappedValue ?? AudioCodec.defaultOrder
        _order = State(initialValue: enabled + AudioCodec.defaultOrder.filter { !enabled.contains($0) })
    }

    private var enabled: [AudioCodec] {
        codecs ?? AudioCodec.defaultOrder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calls offer the checked codecs in this order. Drag to change it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(order) { codec in
                    Toggle(isOn: binding(for: codec)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(codec.displayName)
                            Text(codec.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // A call needs at least one codec
                    .disabled(enabled == [codec])
                    .padding(.vertical, 2)
                    .accessibilityAction(named: "Move Up") { move(codec, by: -1) }
                    .accessibilityAction(named: "Move Down") { move(codec, by: 1) }
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                    set(order.filter(enabled.contains))
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(height: CGFloat(AudioCodec.allCases.count) * 44)

            Button("Restore Defaults") {
                order = AudioCodec.defaultOrder
                codecs = nil
            }
            .disabled(codecs == nil)
        }
        .padding(16)
        .frame(width: 380)
    }

    private func binding(for codec: AudioCodec) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(codec) },
            set: { isOn in
                set(order.filter { $0 == codec ? isOn : enabled.contains($0) })
            }
        )
    }

    private func move(_ codec: AudioCodec, by offset: Int) {
        guard let index = order.firstIndex(of: codec),
              order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        set(order.filter(enabled.contains))
    }

    /// Stores nil when the result is the default, so the account follows
    /// future defaults.
    private func set(_ newValue: [AudioCodec]) {
        codecs = newValue == AudioCodec.defaultOrder ? nil : newValue
    }
}

#Preview {
    AudioCodecEditor(codecs: .constant([.pcma, .opus]))
}
