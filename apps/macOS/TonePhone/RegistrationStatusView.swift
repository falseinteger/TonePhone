//
//  RegistrationStatusView.swift
//  TonePhone
//
//  Displays the current SIP registration status with a colored indicator.
//

import SwiftUI

/// A view that displays the registration status with a colored indicator.
struct RegistrationStatusView: View {
    let status: RegistrationStatus

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator circle
            Circle()
                .fill(status.indicatorColor)
                .frame(width: 10, height: 10)

            // Status text
            Text(status.displayText)
                .font(.system(.body))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

#Preview("Not Configured") {
    RegistrationStatusView(status: .notConfigured)
        .padding()
}

#Preview("Registering") {
    RegistrationStatusView(status: .registering)
        .padding()
}

#Preview("Registered") {
    RegistrationStatusView(status: .registered)
        .padding()
}

#Preview("Failed") {
    RegistrationStatusView(status: .failed(reason: "Connection timeout"))
        .padding()
}
