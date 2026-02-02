//
//  SettingsFormComponents.swift
//  TonePhone
//
//  Shared UI components for settings forms.
//

import SwiftUI

/// A section container for grouping related settings.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

/// A horizontal row with a label and control content.
struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A text field row for settings.
struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SettingsRow(label: label) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// A toggle row with label and description.
struct SettingsToggle: View {
    let label: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
