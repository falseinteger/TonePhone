//
//  ActiveAccountView.swift
//  TonePhone
//
//  Main screen when connected to an account.
//

import SwiftUI

/// Screen displayed when connected to a SIP account: a dial field,
/// recent calls, and calls in progress.
struct ActiveAccountView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var dialInput = ""
    @State private var isKeypadPresented = false
    @State private var selectedTab: Tab = .recents

    private enum Tab: Hashable {
        case recents
        case calls
    }

    private var hasCalls: Bool { !viewModel.activeCalls.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let reason) = viewModel.registrationStatus {
                connectionProblemBanner(reason)
            }

            DialField(input: $dialInput) { input in
                viewModel.dial(input)
            }
            .padding(12)

            if hasCalls {
                Picker("View", selection: $selectedTab) {
                    Text("Recents").tag(Tab.recents)
                    Text("Calls (\(viewModel.activeCalls.count))").tag(Tab.calls)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .help("Switch between recent calls and calls in progress")
            }

            Divider()

            if hasCalls && selectedTab == .calls {
                ActiveCallsListView(viewModel: viewModel)
            } else {
                CallHistoryView(viewModel: viewModel) { uri in
                    viewModel.dial(uri)
                }
            }
        }
        .navigationTitle(viewModel.activeAccount?.title ?? "TonePhone")
        .navigationSubtitle(statusSubtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isKeypadPresented.toggle()
                } label: {
                    Label("Keypad", systemImage: "circle.grid.3x3")
                }
                .keyboardShortcut("k")
                .help("Keypad (⌘K)")
                .popover(isPresented: $isKeypadPresented, arrowEdge: .bottom) {
                    DialKeypadPopover(input: $dialInput) { input in
                        isKeypadPresented = false
                        viewModel.dial(input)
                    }
                }
            }
        }
        .onChange(of: viewModel.activeCalls.count) { count in
            // Show calls in progress when a call is waiting; return to recents when none are left
            if count == 0 {
                selectedTab = .recents
            } else if viewModel.activeCalls.values.contains(where: { $0.isIncomingRinging }) {
                selectedTab = .calls
            }
        }
    }

    private var statusSubtitle: String {
        guard let account = viewModel.activeAccount else { return "" }
        switch viewModel.registrationStatus {
        case .registered:
            return account.address
        case .failed:
            return "Not Connected"
        default:
            return viewModel.registrationStatus.displayText
        }
    }

    /// Shown when the server drops the registration while the account is in use.
    private func connectionProblemBanner(_ reason: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not connected")
                    .font(.headline)
                Text(reason ?? "TonePhone will keep trying to reconnect.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Reconnect") {
                if let account = viewModel.activeAccount {
                    viewModel.startConnection(for: account)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.orange.opacity(0.12))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ActiveAccountView(viewModel: AppViewModel.shared)
        .frame(width: 380, height: 520)
}
