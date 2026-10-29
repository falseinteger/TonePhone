//
//  ContentView.swift
//  TonePhone
//
//  Main window content.
//

import SwiftUI

/// Main window content. Switches screens based on app state.
struct ContentView: View {
    @ObservedObject private var viewModel = AppViewModel.shared

    var body: some View {
        content
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
            .alert(alertTitle, isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(alertMessage)
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
        }
    }

    // MARK: - Alert

    /// The first sentence of the error is the alert title; the rest is the message.
    private var alertParts: (title: String, message: String) {
        let text = viewModel.errorMessage ?? ""
        if let range = text.range(of: ". ") {
            return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
        }
        return (text.hasSuffix(".") ? String(text.dropLast()) : text, "")
    }

    private var alertTitle: String { alertParts.title }
    private var alertMessage: String { alertParts.message }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 860, height: 560)
}
