//
//  STUNServerListEditor.swift
//  TonePhone
//
//  Editable list of STUN server addresses.
//

import SwiftUI

struct STUNServerListEditor: View {
    @Binding var servers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(servers.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 8) {
                    TextField("stun:server:port", text: binding(for: index))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    if servers.count > 1 {
                        Button {
                            servers.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove server")
                    }
                }
            }

            Button {
                servers.append("")
            } label: {
                Label("Add Server", systemImage: "plus.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { servers.indices.contains(index) ? servers[index] : "" },
            set: { newValue in
                if servers.indices.contains(index) {
                    servers[index] = newValue
                }
            }
        )
    }
}

#Preview("STUN Server List") {
    struct Wrapper: View {
        @State var servers = ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]
        var body: some View {
            STUNServerListEditor(servers: $servers)
                .padding()
                .frame(width: 400)
        }
    }
    return Wrapper()
}
