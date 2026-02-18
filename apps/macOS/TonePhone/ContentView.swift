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
/// Follows macOS Human Interface Guidelines for window structure.
struct ContentView: View {
    @ObservedObject private var viewModel = AppViewModel.shared

    var body: some View {
        content
            .frame(minWidth: 280, minHeight: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
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
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.currentScreen {
        case .connecting:
            LaunchConnectingView(viewModel: viewModel)
        case .accountList:
            AccountListView(viewModel: viewModel)
        case .activeAccount:
            ActiveAccountView(viewModel: viewModel)
        case .activeCall:
            ActiveCallView(viewModel: viewModel)
        }
    }

    // MARK: - Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 320, height: 480)
}
