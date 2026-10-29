//
//  ActiveCallsListView.swift
//  TonePhone
//
//  List of calls in progress, including calls waiting to be answered.
//

import SwiftUI

/// Lists all calls in progress. Double-click or Return opens a call.
struct ActiveCallsListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selection: CallID?

    private var calls: [AppViewModel.CallInfo] {
        viewModel.activeCalls.values
            .filter {
                if case .ended = $0.state { return false }
                return $0.state != .idle
            }
            .sorted { lhs, rhs in
                if priority(lhs.state) != priority(rhs.state) {
                    return priority(lhs.state) < priority(rhs.state)
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }
    }

    private func priority(_ state: UICallState) -> Int {
        switch state {
        case .incoming: return 0
        case .established: return 1
        case .outgoing, .early: return 2
        case .held: return 3
        default: return 4
        }
    }

    var body: some View {
        // Redraw durations every second
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List(selection: $selection) {
                ForEach(calls, id: \.id) { call in
                    ActiveCallRow(call: call, now: context.date, viewModel: viewModel)
                        .tag(call.id)
                }
            }
            .contextMenu(forSelectionType: CallID.self) { ids in
                if let id = ids.first {
                    Button("Show Call") { viewModel.selectCall(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first {
                    viewModel.selectCall(id)
                }
            }
        }
        .overlay {
            if calls.isEmpty {
                Text("No Calls in Progress")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A call in the calls list with its actions.
private struct ActiveCallRow: View {
    let call: AppViewModel.CallInfo
    let now: Date
    @ObservedObject var viewModel: AppViewModel

    private var status: String {
        switch call.state {
        case .incoming: return "Incoming Call"
        case .outgoing: return "Calling…"
        case .early: return "Ringing…"
        case .held: return "On Hold"
        case .established:
            if call.isOnHold { return "On Hold" }
            guard let start = call.startTime else { return "Connected" }
            return AppViewModel.formatDuration(now.timeIntervalSince(start))
        case .idle, .ended: return "Ended"
        }
    }

    private var symbolName: String {
        switch call.state {
        case .incoming: return "phone.arrow.down.left"
        case .held: return "pause.circle"
        case .established: return call.isOnHold ? "pause.circle" : "phone.fill"
        default: return "phone.arrow.up.right"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(call.state == .established && !call.isOnHold ? .green : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(call.labels.title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(status)
                        .monospacedDigit()
                    if call.isMuted {
                        Label("Muted", systemImage: "mic.slash.fill")
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Muted")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            actions
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var actions: some View {
        switch call.state {
        case .incoming:
            Button("Decline") { viewModel.declineCall(call.id) }
            Button("Answer") { viewModel.answerCall(call.id) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        case .held:
            resumeButton
            endButton
        case .established where call.isOnHold:
            resumeButton
            endButton
        case .established:
            Button("Hold") {
                viewModel.setTargetCall(call.id)
                viewModel.toggleHold()
            }
            endButton
        default:
            endButton
        }
    }

    private var resumeButton: some View {
        Button("Resume") {
            viewModel.setTargetCall(call.id)
            viewModel.toggleHold()
        }
    }

    private var endButton: some View {
        Button("End") { viewModel.hangupCall(call.id) }
            .tint(.red)
    }
}

#Preview("Calls List") {
    ActiveCallsListView(viewModel: AppViewModel.shared)
        .frame(width: 360, height: 300)
}
