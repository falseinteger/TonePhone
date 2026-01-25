//
//  ContentView.swift
//  TonePhone
//
//  Main content view for the TonePhone application.
//

import SwiftUI

/// Main content view for the TonePhone application window.
///
/// Manages the navigation between different screens based on app state.
/// Shows account list when not connected, active account view when connected.
struct ContentView: View {
    /// View model that tracks account and registration state.
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        Group {
            switch viewModel.currentScreen {
            case .accountList:
                AccountListView(viewModel: viewModel)
            case .activeAccount:
                ActiveAccountView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.isAccountSheetPresented) {
            AccountConfigView(account: viewModel.selectedAccount)
                .onSave { account, password in
                    viewModel.saveAccount(account, password: password)
                }
                .onDelete { accountID in
                    viewModel.deleteAccount(id: accountID)
                }
        }
        .sheet(isPresented: $viewModel.isConnectionSheetPresented) {
            ConnectionProgressView(viewModel: viewModel)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }
}

#Preview {
    ContentView()
}
