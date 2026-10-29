//
//  STUNServerListEditor.swift
//  TonePhone
//
//  Editable list of STUN server addresses.
//

import SwiftUI

/// Rows for a Form section: one field per server and an Add Server button.
struct STUNServerListEditor: View {
    @Binding var servers: [String]

    var body: some View {
        ForEach(servers.indices, id: \.self) { index in
            HStack {
                TextField("STUN server", text: binding(for: index), prompt: Text("stun.example.com:3478"))
                    .labelsHidden()

                Button {
                    servers.remove(at: index)
                } label: {
                    Label("Remove Server", systemImage: "minus.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(servers.count <= 1)
                .help("Remove server")
            }
        }

        Button("Add Server") {
            servers.append("")
        }
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
