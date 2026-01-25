//
//  ContentView.swift
//  TonePhone
//
//  Main content view for the TonePhone application.
//

import SwiftUI

/// Main content view for the TonePhone application window.
///
/// Displays the app branding and current registration status.
/// The status updates in real-time as account state changes are received.
struct ContentView: View {
    /// View model that tracks account registration state.
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        VStack {
            Spacer()

            // App icon
            Image(systemName: "phone.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("TonePhone")
                .font(.title)
                .padding(.top, 8)

            Spacer()

            // Registration status at the bottom
            RegistrationStatusView(status: viewModel.registrationStatus)
                .padding(.bottom, 20)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
