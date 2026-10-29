//
//  ActiveAccountView.swift
//  TonePhone
//
//  Main window when connected to an account: recents and their detail.
//

import SwiftUI

/// Recent calls on the left, the selected call on the right, like the
/// Phone app. The search field filters recents and dials what is typed.
struct ActiveAccountView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var query = ""
    @State private var filter: RecentsFilter = .all
    @State private var selection: CallRecord.ID?
    @State private var records: [CallRecord] = []
    @State private var dialInput = ""
    @State private var isKeypadPresented = false
    @State private var formatVersion = 0

    private var visibleRecords: [CallRecord] {
        records.filter { record in
            if filter == .missed && record.direction != .missed { return false }
            guard !query.isEmpty else { return true }
            let labels = PhoneNumberService.partyLabels(name: record.remoteName, uri: record.remoteURI)
            let digits = PhoneNumberService.dialableCharacters(of: query)
            return labels.title.localizedCaseInsensitiveContains(query) ||
                (labels.subtitle?.localizedCaseInsensitiveContains(query) ?? false) ||
                (!digits.isEmpty && record.remoteURI.contains(digits))
        }
    }

    private var selectedRecord: CallRecord? {
        records.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            CallHistoryView(
                viewModel: viewModel,
                records: visibleRecords,
                query: query,
                selection: $selection,
                formatVersion: formatVersion
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            .toolbar {
                // In the list's own part of the toolbar, like the Phone app
                ToolbarItem {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(RecentsFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(
                            "Filter",
                            systemImage: filter == .all
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                    .help("Show all calls or only missed calls")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if case .failed(let reason) = viewModel.registrationStatus {
                    connectionProblemBanner(reason)
                }
            }
        } detail: {
            if let record = selectedRecord {
                RecentDetailView(
                    viewModel: viewModel,
                    record: record,
                    allRecords: records,
                    formatVersion: formatVersion
                )
            } else {
                Text("No Call Selected")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .modifier(HideSidebarToggle())
        .navigationTitle(viewModel.activeAccount?.title ?? "TonePhone")
        .navigationSubtitle(statusSubtitle)
        .toolbarTitleMenu {
            AccountSwitcherMenu(viewModel: viewModel)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search or Enter Number")
        .onSubmit(of: .search) {
            let input = query.trimmingCharacters(in: .whitespaces)
            guard !input.isEmpty, visibleRecords.isEmpty || PhoneNumberService.looksLikeAddress(input)
                || !PhoneNumberService.dialableCharacters(of: input).isEmpty else { return }
            viewModel.dial(input)
            query = ""
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.canCallVoicemail {
                    Button {
                        viewModel.callVoicemail()
                    } label: {
                        Label(voicemailLabel, systemImage: voicemailSymbol)
                    }
                    .help(voicemailLabel)
                }

                Button {
                    isKeypadPresented.toggle()
                } label: {
                    Label("Keypad", systemImage: "circle.grid.3x3.fill")
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
        .onAppear(perform: reload)
        .onChange(of: viewModel.activeAccount?.id) { _ in
            selection = nil
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .callHistoryDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phoneNumberFormatDidChange)) { _ in
            formatVersion += 1
        }
    }

    private func reload() {
        guard let accountID = viewModel.activeAccount?.id else {
            records = []
            return
        }
        records = CallHistoryStore.shared.records(for: accountID)
        if selection == nil || !records.contains(where: { $0.id == selection }) {
            selection = records.first?.id
        }
    }

    private var hasNewVoicemail: Bool {
        viewModel.voicemailStatus?.hasNewMessages ?? false
    }

    private var voicemailSymbol: String {
        hasNewVoicemail ? "recordingtape.circle.fill" : "recordingtape"
    }

    private var voicemailLabel: String {
        guard let status = viewModel.voicemailStatus, status.hasNewMessages else {
            return "Call Voicemail"
        }
        if let count = status.newMessages {
            return count == 1 ? "Call Voicemail (1 new message)" : "Call Voicemail (\(count) new messages)"
        }
        return "Call Voicemail (new messages)"
    }

    private var statusSubtitle: String {
        guard let account = viewModel.activeAccount else { return "" }
        switch viewModel.registrationStatus {
        case .registered:
            if let count = viewModel.voicemailStatus?.newMessages, count > 0 {
                return "\(account.address) · \(count) new voicemail" + (count == 1 ? "" : "s")
            }
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
                Text("Not Connected")
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
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}

/// The Phone app has no sidebar button; the list is always shown.
private struct HideSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

/// Accounts in the window title menu: switch, edit, add, disconnect.
struct AccountSwitcherMenu: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ForEach(viewModel.accounts) { account in
            Button {
                if account.id != viewModel.activeAccount?.id {
                    viewModel.startConnection(for: account)
                }
            } label: {
                if account.id == viewModel.activeAccount?.id {
                    Label(account.title, systemImage: "checkmark")
                } else {
                    Text(account.title)
                }
            }
        }

        Divider()

        if let account = viewModel.activeAccount {
            Button("Edit \(account.title)…") {
                viewModel.showEditAccountSheet(for: account)
            }
        }
        Button("Add Account…") {
            viewModel.showAddAccountSheet()
        }

        Divider()

        Button("Disconnect") {
            viewModel.disconnect()
        }
    }
}

#Preview {
    ActiveAccountView(viewModel: AppViewModel.shared)
        .frame(width: 820, height: 540)
}
