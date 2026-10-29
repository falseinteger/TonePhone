//
//  CallHistoryView.swift
//  TonePhone
//
//  Recent calls list and the detail for the selected call.
//

import SwiftUI

/// Which recent calls the list shows.
enum RecentsFilter: String, CaseIterable, Identifiable {
    case all = "All Calls"
    case missed = "Missed"

    var id: Self { self }
}

/// Consecutive calls with the same party and direction, shown as one row
/// like the Phone app ("Sarah Chen (3)").
struct RecentGroup: Identifiable {
    let records: [CallRecord]

    var latest: CallRecord { records[0] }
    var id: CallRecord.ID { latest.id }

    static func group(_ records: [CallRecord]) -> [RecentGroup] {
        var groups: [[CallRecord]] = []
        for record in records {
            if let last = groups.last?.last,
               last.direction == record.direction,
               PhoneNumberService.userPart(ofURI: last.remoteURI) == PhoneNumberService.userPart(ofURI: record.remoteURI),
               Calendar.current.isDate(last.timestamp, inSameDayAs: record.timestamp) {
                groups[groups.count - 1].append(record)
            } else {
                groups.append([record])
            }
        }
        return groups.map(RecentGroup.init)
    }
}

/// Recent calls for the active account, filtered and searched.
///
/// Double-click or Return calls back; the context menu offers Call, Copy and Delete.
struct CallHistoryView: View {
    @ObservedObject var viewModel: AppViewModel
    let records: [CallRecord]
    let query: String
    @FocusState private var isListFocused: Bool

    private var groups: [RecentGroup] { RecentGroup.group(records) }
    @Binding var selection: CallRecord.ID?
    let formatVersion: Int

    @State private var showClearConfirmation = false

    /// What the user typed, when it can be dialed.
    private var dialableQuery: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              PhoneNumberService.looksLikeAddress(trimmed) ||
              !PhoneNumberService.dialableCharacters(of: trimmed).isEmpty
        else { return nil }
        return trimmed
    }

    var body: some View {
        List(selection: $selection) {
            if let number = dialableQuery {
                Button {
                    viewModel.dial(number)
                } label: {
                    Label {
                        Text("Call \(PhoneNumberService.formatPartial(number))")
                    } icon: {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.green)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .help("Call (Return)")
            }

            Section {
                ForEach(groups) { group in
                    CallHistoryRow(
                        record: group.latest,
                        count: group.records.count,
                        isSelected: selection == group.id,
                        formatVersion: formatVersion
                    ) {
                        viewModel.dial(group.latest.remoteURI)
                    }
                    .tag(group.id)
                }
            } header: {
                if dialableQuery != nil && !records.isEmpty {
                    Text("Recents")
                }
            }
        }
        .contextMenu(forSelectionType: CallRecord.ID.self) { ids in
            let selected = groups.filter { ids.contains($0.id) }.map(\.latest)
            if let record = selected.first, selected.count == 1 {
                Button("Call \(CallHistoryRow.title(for: record))") {
                    viewModel.dial(record.remoteURI)
                }
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.remoteURI, forType: .string)
                }
                Divider()
            }
            if !selected.isEmpty {
                Button("Delete from Recents", role: .destructive) {
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
                viewModel.dial(record.remoteURI)
            }
        }
        .onDeleteCommand {
            if let selection { delete([selection]) }
        }
        // On the window background with a gray selection, like the Phone app,
        // rather than a sidebar with an accent-colored selection
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.background)
        .focused($isListFocused)
        .onAppear { isListFocused = true }
        .overlay {
            if records.isEmpty && dialableQuery == nil {
                emptyState
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
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(query.isEmpty ? "No Recent Calls" : "No Results")
                .font(.title3.weight(.semibold))
            Text(query.isEmpty ? "Calls you make and receive appear here." : "Type a number to call it.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    /// Deletes the selected rows, including every call grouped into them.
    private func delete(_ ids: Set<CallRecord.ID>) {
        for group in groups where ids.contains(group.id) {
            for record in group.records {
                CallHistoryStore.shared.deleteRecord(id: record.id)
            }
        }
        if let selection, ids.contains(selection) { self.selection = nil }
        NotificationCenter.default.post(name: .callHistoryDidChange, object: nil)
    }
}

/// A row in the recents list: avatar, who, how, when, and a call button.
struct CallHistoryRow: View {
    let record: CallRecord
    /// Number of calls grouped into this row.
    var count = 1
    var isSelected = false
    /// Changes when number formatting settings change, to re-render.
    let formatVersion: Int
    let onCall: () -> Void

    static func title(for record: CallRecord) -> String {
        PhoneNumberService.partyLabels(name: record.remoteName, uri: record.remoteURI).title
    }

    private var isMissed: Bool { record.direction == .missed }

    var body: some View {
        HStack(spacing: 10) {
            CallerAvatar(title: Self.title(for: record), size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(Self.title(for: record))
                    .font(.body.weight(.medium))
                    .foregroundStyle(isMissed ? .red : .primary)
                    .lineLimit(1)

                // Image inside Text so the list doesn't tint the arrow
                Text("\(Image(systemName: record.direction.arrowSymbol)) \(count > 1 ? "\(detail) (\(count))" : detail)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // VoiceOver would read the arrow's symbol name
                    .accessibilityLabel(spokenDetail)
            }

            Spacer(minLength: 4)

            Text(Self.shortDate(record.timestamp))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            RoundCallButton(isOnSelection: isSelected, action: onCall)
                .help("Call \(Self.title(for: record))")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click to call back")
    }

    /// The number when a name is shown, otherwise the kind of call.
    private var detail: String {
        if let subtitle = PhoneNumberService.partyLabels(name: record.remoteName, uri: record.remoteURI).subtitle {
            return subtitle
        }
        return record.direction.title
    }

    /// The second line for VoiceOver: the kind of call instead of the arrow.
    private var spokenDetail: String {
        let kind = record.direction.title
        let text = detail == kind ? kind : "\(kind), \(detail)"
        return count > 1 ? "\(text), \(count) calls" : text
    }

    /// "3:16 PM", "Yesterday", "Tuesday" or a date, like the Phone app.
    static func shortDate(_ date: Date) -> String {
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

/// Small round phone button at the end of a row.
struct RoundCallButton: View {
    /// Drawn on a selected row, where the accent color would not show.
    var isOnSelection = false
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(isOnSelection ? Color.white : Color.accentColor)
                .frame(width: size, height: size)
                .background(Circle().fill(isOnSelection ? AnyShapeStyle(Color.white.opacity(0.25)) : AnyShapeStyle(.quaternary)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call")
    }
}

extension CallDirection {
    var title: String {
        switch self {
        case .missed: return "Missed"
        case .inbound: return "Incoming"
        case .outbound: return "Outgoing"
        }
    }

    var arrowSymbol: String {
        switch self {
        case .outbound: return "arrow.up.right"
        case .inbound, .missed: return "arrow.down.left"
        }
    }
}

// MARK: - Detail

/// The selected recent call: who it was, a call button, and every call
/// with the same party.
struct RecentDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let record: CallRecord
    let allRecords: [CallRecord]
    let formatVersion: Int

    private var labels: (title: String, subtitle: String?) {
        PhoneNumberService.partyLabels(name: record.remoteName, uri: record.remoteURI)
    }

    /// Calls with the same party, newest first.
    private var history: [CallRecord] {
        let user = PhoneNumberService.userPart(ofURI: record.remoteURI)
        return allRecords.filter { PhoneNumberService.userPart(ofURI: $0.remoteURI) == user }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    CallerAvatar(title: labels.title, size: 96)

                    Text(labels.title)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    if let subtitle = labels.subtitle {
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 24)

                CircleActionButton(title: "Call", systemImage: "phone.fill", tint: .green) {
                    viewModel.dial(record.remoteURI)
                }

                GroupBox {
                    VStack(spacing: 0) {
                        Text("Call History")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        ForEach(Array(history.enumerated()), id: \.element.id) { index, call in
                            Divider()
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(call.direction == .missed ? "Missed Call" : "\(call.direction.title) Call")
                                        .foregroundStyle(call.direction == .missed ? .red : .primary)
                                    if call.duration > 0 {
                                        Text(Self.durationText(call.duration))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Self.dayAndTime(call.timestamp))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                    }
                }

                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isPhoneNumber ? "phone" : "address")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(contactValue)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        RoundCallButton(size: 28) {
                            viewModel.dial(record.remoteURI)
                        }
                        .help("Call")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .id(formatVersion)
        .onCopyCommand {
            let value = isPhoneNumber
                ? PhoneNumberService.userPart(ofURI: record.remoteURI)
                : PhoneNumberService.address(ofURI: record.remoteURI)
            return [NSItemProvider(object: value as NSString)]
        }
    }

    private var isPhoneNumber: Bool {
        !PhoneNumberService.looksLikeAddress(PhoneNumberService.userPart(ofURI: record.remoteURI))
    }

    /// The formatted number, or the full address when it isn't a number.
    private var contactValue: String {
        isPhoneNumber
            ? (labels.subtitle ?? labels.title)
            : PhoneNumberService.address(ofURI: record.remoteURI)
    }

    /// "4:14 PM" today, otherwise "Tuesday · 4:14 PM", like the Phone app.
    static func dayAndTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return time }
        return "\(CallHistoryRow.shortDate(date)) · \(time)"
    }

    /// "33 seconds", "2 minutes", "1 hour, 5 minutes".
    static func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : (duration >= 60 ? [.minute, .second] : [.second])
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? ""
    }
}

/// Round button with a caption underneath, used in the recent call detail
/// and the call window.
struct CircleActionButton: View {
    let title: String
    let systemImage: String
    /// Fill color; nil uses the neutral control color.
    let tint: Color?
    var isOn = false
    var size: CGFloat = 48
    /// Focus binding for the button, to choose which one has focus first.
    var focus: FocusState<Bool>.Binding?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Only the circle is the button, so the keyboard focus ring
            // follows the circle rather than circle and caption
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: size, height: size)
                    .background(Circle().fill(background))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(OptionalFocus(focus: focus))
            .accessibilityLabel(title)
            .accessibilityAddTraits(isOn ? .isSelected : [])

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private var foreground: Color {
        if tint != nil { return .white }
        return isOn ? Color(nsColor: .windowBackgroundColor) : .primary
    }

    private var background: AnyShapeStyle {
        if let tint { return AnyShapeStyle(tint) }
        return isOn ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.quaternary)
    }
}

private struct OptionalFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus)
        } else {
            content
        }
    }
}

extension Notification.Name {
    static let callHistoryDidChange = Notification.Name("com.tonephone.callHistoryDidChange")
}
