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
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(servers.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    TextField("STUN server", text: binding(for: index), prompt: Text("stun:server:port"))
                        .labelsHidden()
                        .font(.body.monospaced())

                    Button {
                        servers.remove(at: index)
                    } label: {
                        Label("Remove Server", systemImage: "minus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(servers.count <= 1)
                    .help("Remove server")
                }
            }

            Button {
                servers.append("")
            } label: {
                Label("Add Server", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: 280)
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { servers.indices.contains(index) ? servers[index] : "" },
            set: { newValue in
                if servers.indices.contains(index) {
                    servers[index] = newValue.trimmingCharacters(in: .whitespaces)
                }
            }
        )
    }
}
