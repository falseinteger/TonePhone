//
//  CallHistoryView.swift
//  TonePhone
//
//  View displaying call history with incoming and outgoing calls.
//

import SwiftUI

/// View displaying the call history list.
struct CallHistoryView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var callRecords: [CallRecord] = []
    @State private var selectedFilter: CallFilter = .all

    enum CallFilter: String, CaseIterable {
        case all = "All"
        case incoming = "Incoming"
        case outgoing = "Outgoing"
        case missed = "Missed"
    }

    var filteredRecords: [CallRecord] {
        switch selectedFilter {
        case .all:
            return callRecords
        case .incoming:
            return callRecords.filter { $0.direction == .incoming }
        case .outgoing:
            return callRecords.filter { $0.direction == .outgoing }
        case .missed:
            return callRecords.filter { $0.outcome == .missed }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with filter
            header

            Divider()

            // Call list
            if filteredRecords.isEmpty {
                emptyState
            } else {
                callList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadCallHistory()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Recent Calls")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(CallFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            // Clear button
            if !callRecords.isEmpty {
                Button {
                    clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear call history")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: "phone.badge.checkmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(emptyStateMessage)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        switch selectedFilter {
        case .all:
            return "No recent calls"
        case .incoming:
            return "No incoming calls"
        case .outgoing:
            return "No outgoing calls"
        case .missed:
            return "No missed calls"
        }
    }

    // MARK: - Call List

    private var callList: some View {
        List {
            ForEach(filteredRecords) { record in
                CallRecordRow(record: record) {
                    // Call back action
                    viewModel.makeCall(to: record.remoteURI)
                }
                .contextMenu {
                    Button("Call") {
                        viewModel.makeCall(to: record.remoteURI)
                    }

                    Divider()

                    Button("Copy Number") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.remoteURI, forType: .string)
                    }

                    Divider()

                    Button("Delete", role: .destructive) {
                        deleteRecord(record)
                    }
                }
            }
            .onDelete { indexSet in
                deleteRecords(at: indexSet)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func loadCallHistory() {
        callRecords = CallHistoryStore.shared.loadHistory()
    }

    private func clearHistory() {
        CallHistoryStore.shared.clearHistory()
        callRecords = []
    }

    private func deleteRecord(_ record: CallRecord) {
        CallHistoryStore.shared.deleteRecord(id: record.id)
        callRecords.removeAll { $0.id == record.id }
    }

    private func deleteRecords(at indexSet: IndexSet) {
        let recordsToDelete = indexSet.map { filteredRecords[$0] }
        for record in recordsToDelete {
            CallHistoryStore.shared.deleteRecord(id: record.id)
        }
        callRecords.removeAll { record in
            recordsToDelete.contains { $0.id == record.id }
        }
    }
}

// MARK: - Call Record Row

private struct CallRecordRow: View {
    let record: CallRecord
    let onCall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Direction indicator
            directionIcon
                .frame(width: 24)

            // Call info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(record.outcome == .missed ? .red : .primary)
                        .lineLimit(1)

                    if record.outcome == .missed {
                        Text("Missed")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }

                HStack(spacing: 4) {
                    Text(record.formattedTime)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if let duration = record.formattedDuration {
                        Text("(\(duration))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Call button
            Button {
                onCall()
            } label: {
                Image(systemName: "phone.fill")
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .help("Call \(record.displayName)")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var directionIcon: some View {
        Group {
            switch record.direction {
            case .incoming:
                Image(systemName: "phone.arrow.down.left")
                    .foregroundColor(record.outcome == .missed ? .red : .blue)
            case .outgoing:
                Image(systemName: "phone.arrow.up.right")
                    .foregroundColor(.green)
            }
        }
        .font(.system(size: 14))
    }
}

// MARK: - Preview

#Preview("Call History") {
    CallHistoryView(viewModel: AppViewModel())
        .frame(width: 320, height: 400)
}

#Preview("Call History Row") {
    VStack {
        CallRecordRow(
            record: CallRecord(
                direction: .outgoing,
                outcome: .answered,
                remoteURI: "sip:1234@example.com",
                remoteName: "John Doe",
                duration: 125
            ),
            onCall: {}
        )

        CallRecordRow(
            record: CallRecord(
                direction: .incoming,
                outcome: .missed,
                remoteURI: "sip:5678@example.com",
                remoteName: nil
            ),
            onCall: {}
        )
    }
    .padding()
}
