//
//  CallHistoryView.swift
//  TonePhone
//
//  Recent calls list for the active account.
//

import SwiftUI

/// Displays the call history for the current account.
struct CallHistoryView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var records: [CallRecord] = []
    let onRedial: (String) -> Void

    var body: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .callHistoryDidChange)) { _ in
            reload()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No recent calls")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            // Header with clear button
            HStack {
                Text("Recents")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear") {
                    guard let accountID = viewModel.activeAccount?.id else { return }
                    CallHistoryStore.shared.clearHistory(for: accountID)
                    NotificationCenter.default.post(name: .callHistoryDidChange, object: nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        callRow(record)
                        if record.id != records.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func callRow(_ record: CallRecord) -> some View {
        HStack(spacing: 10) {
            // Direction icon
            directionIcon(record.direction)
                .frame(width: 20)

            // Name / number
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: record))
                    .font(.system(size: 13))
                    .foregroundColor(record.direction == .missed ? .red : .primary)
                    .lineLimit(1)

                Text(formattedDate(record.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Duration
            if record.duration > 0 {
                Text(formattedDuration(record.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Redial button
            Button {
                onRedial(record.remoteURI)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Call \(displayName(for: record))")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func directionIcon(_ direction: CallDirection) -> some View {
        Group {
            switch direction {
            case .outbound:
                Image(systemName: "phone.arrow.up.right")
                    .foregroundColor(.secondary)
            case .inbound:
                Image(systemName: "phone.arrow.down.left")
                    .foregroundColor(.secondary)
            case .missed:
                Image(systemName: "phone.arrow.down.left")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 13))
    }

    private func displayName(for record: CallRecord) -> String {
        if let name = record.remoteName, !name.isEmpty {
            return PhoneNumberService.formatForDisplay(name)
        }
        return PhoneNumberService.formatForDisplay(record.remoteURI)
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, " + date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func reload() {
        guard let accountID = viewModel.activeAccount?.id else {
            records = []
            return
        }
        records = CallHistoryStore.shared.records(for: accountID)
    }
}

extension Notification.Name {
    static let callHistoryDidChange = Notification.Name("com.tonephone.callHistoryDidChange")
}
