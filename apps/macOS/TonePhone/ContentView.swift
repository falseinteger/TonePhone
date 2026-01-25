//
//  ContentView.swift
//  TonePhone
//
//  Main content view for the TonePhone application.
//

import SwiftUI

struct ContentView: View {
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
