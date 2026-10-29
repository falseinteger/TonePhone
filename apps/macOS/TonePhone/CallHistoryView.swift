//
//  CallHistoryView.swift
//  TonePhone
//
//  Recent calls list for the active account.
//

import SwiftUI

/// Displays the call history for the current account.
///
/// Double-click or Return calls back; the context menu offers Call, Copy and Delete.
struct CallHistoryView: View {
    @ObservedObject var viewModel: AppViewModel
    let onRedial: (String) -> Void

    @State private var records: [CallRecord] = []
    @State private var selection = Set<CallRecord.ID>()
    @State private var showClearConfirmation = false
    @State private var formatVersion = 0

    var body: some View {
        List(selection: $selection) {
            ForEach(records) { record in
                CallHistoryRow(record: record, formatVersion: formatVersion)
                    .tag(record.id)
            }
        }
        .contextMenu(forSelectionType: CallRecord.ID.self) { ids in
            let selected = records.filter { ids.contains($0.id) }
            if let record = selected.first, selected.count == 1 {
                Button("Call \(CallHistoryRow.title(for: record))") {
                    onRedial(record.remoteURI)
                }
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.remoteURI, forType: .string)
                }
                Divider()
            }
            if !selected.isEmpty {
                Button(selected.count == 1 ? "Delete" : "Delete \(selected.count) Calls", role: .destructive) {
                    delete(ids)
                }
            }
            if !records.isEmpty {
                Button("Clear All Recents…") {
                    showClearConfirmation = true
                }
            }
        } primaryAction: { ids in
            if let record = records.first(where: { ids.contains($0.id) }) {
                onRedial(record.remoteURI)
            }
        }
        .onDeleteCommand {
            delete(selection)
        }
        .overlay {
            if records.isEmpty {
                VStack(spacing: 6) {
                    Text("No Recent Calls")
                        .font(.title3)
                    Text("Calls you make and receive appear here.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
        }
        .confirmationDialog("Clear all recent calls?", isPresented: $showClearConfirmation) {
            Button("Clear Recents", role: .destructive) {
                guard let accountID = viewModel.activeAccount?.id else { return }
                CallHistoryStore.shared.clearHistory(for: accountID)
                NotificationCenter.default.post(name: .callHistoryDidChange, object: nil)
            }
        } message: {
            Text("This can’t be undone.")
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .callHistoryDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phoneNumberFormatDidChange)) { _ in
            formatVersion += 1
        }
    }

    private func delete(_ ids: Set<CallRecord.ID>) {
        for id in ids {
            CallHistoryStore.shared.deleteRecord(id: id)
        }
        selection.subtract(ids)
        NotificationCenter.default.post(name: .callHistoryDidChange, object: nil)
    }

    private func reload() {
        guard let accountID = viewModel.activeAccount?.id else {
            records = []
            return
        }
        records = CallHistoryStore.shared.records(for: accountID)
    }
}

/// A row in the recents list.
struct CallHistoryRow: View {
    let record: CallRecord
    /// Changes when number formatting settings change, to re-render.
    let formatVersion: Int

    static func title(for record: CallRecord) -> String {
        PhoneNumberService.partyLabels(name: record.remoteName, uri: record.remoteURI).title
    }

    private var isMissed: Bool { record.direction == .missed }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(isMissed ? .red : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: record))
                    .foregroundStyle(isMissed ? .red : .primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formattedDate(record.timestamp))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click to call back")
    }

    private var symbolName: String {
        switch record.direction {
        case .outbound: return "phone.arrow.up.right"
        case .inbound: return "phone.arrow.down.left"
        case .missed: return "phone.down"
        }
    }

    /// "Missed", "Outgoing · 2:15", plus the number when a name is shown.
    private var detail: String {
        var parts: [String] = []
        switch record.direction {
        case .missed: parts.append("Missed")
        case .inbound: parts.append("Incoming")
        case .outbound: parts.append("Outgoing")
        }
        if record.duration > 0 {
            parts.append(AppViewModel.formatDuration(record.duration))
        }
        if let subtitle = PhoneNumberService.partyLabels(name: record.remoteName, uri: record.remoteURI).subtitle {
            parts.append(subtitle)
        }
        return parts.joined(separator: " · ")
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

extension Notification.Name {
    static let callHistoryDidChange = Notification.Name("com.tonephone.callHistoryDidChange")
}
